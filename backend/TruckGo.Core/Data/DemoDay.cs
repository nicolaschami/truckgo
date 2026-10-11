using Microsoft.EntityFrameworkCore;
using TruckGo.Integration;

namespace TruckGo.Data;

/// <summary>
/// DEMO ONLY — "Load a demo day" on the live board (development, Admin).
///
/// Plays a realistic moment of a working day for the DEMO company, relative
/// to now, so the live board has something to show before the driver app
/// sends real statuses: trucks loading, one waiting too long, two on the road
/// (one late), one arrived at a site, one unloading for too long, and two
/// deliveries already done with their weighbridge readings.
///
/// The deliveries are created through the normal door (MasterDataImport), as
/// the other system would; their statuses are then set directly, as the app
/// would. Running it again resets the times. Deliveries numbered 9001xx are
/// the demo day's; nothing else is touched.
/// </summary>
public static class DemoDay
{
    public static async Task PlayAsync(TruckGoDb db, DateTime nowUtc)
    {
        var company = await db.Companies.SingleAsync(c => c.Code == SeedData.CompanyCode);
        var import = new MasterDataImport(db, TimeProvider.System);
        DateTime Ago(int minutes) => nowUtc.AddMinutes(-minutes);

        // number, plant, customer, ship-to, truck, trailer, material, tons,
        // planned arrival (minutes from now), status, in that status since (minutes ago)
        var scenes = new (string No, string Plant, string Cust, string Ship, string Truck, string Trailer,
            string Material, double Tons, int PlannedIn, DeliveryStatus Status, int SinceMin)[]
        {
            ("900101", "QN2", "100318", "100318-01", "TG-5821", "TR-1002", "AC 20 close surface 100/150", 19.5,  70, DeliveryStatus.Loading,        12),
            ("900102", "QN2", "100245", "100245-02", "MN-7740", "TR-1003", "AC 32 dense base 40/60",      21.0,  90, DeliveryStatus.AtPlant,        41),  // waiting too long
            ("900103", "QS1", "100577", "100577-01", "RT-3092", "TR-1004", "SMA 14 surface",              22.0,  25, DeliveryStatus.InTransit,      18),
            ("900104", "QN2", "100245", "100245-01", "KL-1188", "TR-1005", "AC 32 dense base 40/60",      20.0, -30, DeliveryStatus.InTransit,      55),  // late
            ("900105", "QS1", "100577", "100577-01", "ZX-9054", "TR-1006", "SMA 14 surface",              18.0,  -5, DeliveryStatus.ArrivedAtSite,   8),
            ("900106", "QN2", "100318", "100318-01", "PL-4417", "TR-1001", "AC 20 close surface 100/150", 20.0, -50, DeliveryStatus.Unloading,      52),  // unloading too long
            ("900107", "QS1", "100245", "100245-02", "BC-2260", "TR-1001", "SMA 14 surface",              24.0, 120, DeliveryStatus.AtPlant,        95),  // twice the limit
            ("900108", "QN2", "100245", "100245-01", "TG-5821", "TR-1002", "AC 32 dense base 40/60",      20.0, -180, DeliveryStatus.Delivered,    140),
            ("900109", "QS1", "100318", "100318-01", "RT-3092", "TR-1004", "SMA 14 surface",              22.0, -150, DeliveryStatus.Delivered,    110),
        };

        foreach (var s in scenes)
        {
            var planned = nowUtc.AddMinutes(s.PlannedIn);
            // Created or re-planned through the door, as the other system would
            var delivery = await import.SaveDeliveryAsync(company.Id, new DeliveryMessage(
                s.Plant, s.No, "DEMO-" + s.No, s.Cust, s.Ship, s.Material, s.Tons,
                planned, planned.AddMinutes(-20), planned.AddMinutes(20), s.Truck, s.Trailer, 25,
                "Demo day — not a real delivery."));

            // The weighbridge readings of the delivered ones (tare, then gross)
            if (s.Status == DeliveryStatus.Delivered && !await db.Weighings.AnyAsync(w => w.DeliveryId == delivery.Id))
            {
                await import.SaveWeighingAsync(company.Id, new WeighingMessage(s.Plant, s.No, WeighingKind.First, 14.1, Ago(s.SinceMin + 70), $"T-{s.No}-1", "WB-1"));
                await import.SaveWeighingAsync(company.Id, new WeighingMessage(s.Plant, s.No, WeighingKind.Second, 14.1 + s.Tons - 0.3, Ago(s.SinceMin + 55), $"T-{s.No}-2", "WB-1"));
            }

            // The status, as the app would have moved it, and since when
            delivery.Status = s.Status;
            delivery.UpdatedAt = Ago(s.SinceMin);

            // The GPS trail the app would have sent (replaced on every run)
            await db.Positions.Where(p => p.DeliveryId == delivery.Id).ExecuteDeleteAsync();
            var plant = await db.Plants.SingleAsync(p => p.Id == delivery.PlantId);
            var site = await db.ShipTos.SingleAsync(x => x.Id == delivery.ShipToId);
            db.Positions.AddRange(Trail(company.Id, delivery.Id, s.Truck, s.Status, s.SinceMin, nowUtc,
                (plant.Latitude, plant.Longitude), (site.Latitude, site.Longitude), int.Parse(s.No)));
        }
        await db.SaveChangesAsync();
    }

    // ------------------------------------------------------------------
    // The demo GPS trails: one point a minute, like the app sends them
    // ------------------------------------------------------------------

    private const int LoadingMinutes = 25;   // time spent at the plant before leaving
    private const int UnloadedMinutes = 10;  // "unloading since" starts this long after arrival
    private const int SiteMinutes = 25;      // time at the site for a delivered one

    /// <summary>
    /// A believable trail for one delivery, ending now (or when it was
    /// delivered): at the plant, along a curved road to the site, at the site.
    /// The late truck (on the road longer than the trip takes) gets a
    /// 20-minute stop half way — it shows on the trace as an unexpected stop.
    /// </summary>
    private static IEnumerable<GpsPosition> Trail(Guid companyId, Guid deliveryId, string plate,
        DeliveryStatus status, int sinceMin, DateTime now,
        (double Lat, double Lng) plant, (double Lat, double Lng) site, int seed)
    {
        var rnd = new Random(seed);
        var roadKm = Queries.Geo.DistanceM(plant.Lat, plant.Lng, site.Lat, site.Lng) / 1000 * 1.3; // roads are not straight
        var travel = Math.Max(15, (int)(roadKm / 45 * 60));                                         // at about 45 km/h
        var points = new List<(int MinutesAgo, double Lat, double Lng, double Speed)>();

        void Stay(int fromAgo, int toAgo, (double Lat, double Lng) at, double jitterM)
        {
            for (var m = fromAgo; m > toAgo; m--)
            {
                var (lat, lng) = Jitter(at, jitterM, rnd);
                points.Add((m, lat, lng, rnd.NextDouble() * 3));
            }
        }

        // Drive from the plant (minute fromAgo) towards the site, reaching
        // "progress" (0..1) at minute toAgo; an optional stop half way
        void Drive(int fromAgo, int toAgo, double progress, int stopMinutes)
        {
            var total = fromAgo - toAgo;
            var moving = Math.Max(1, total - stopMinutes);
            var covered = 0;
            for (var m = fromAgo; m > toAgo; m--)
            {
                var elapsed = fromAgo - m;
                var stopped = stopMinutes > 0 && elapsed >= moving / 2 && elapsed < moving / 2 + stopMinutes;
                if (!stopped) covered++;
                var f = progress * covered / moving;
                var (lat, lng) = Jitter(Road(plant, site, f, seed), stopped ? 6 : 10, rnd);
                points.Add((m, lat, lng, stopped ? 0 : 38 + rnd.NextDouble() * 22));
            }
        }

        switch (status)
        {
            case DeliveryStatus.AtPlant:
                Stay(sinceMin, 0, plant, 35);
                break;
            case DeliveryStatus.Loading:
                Stay(sinceMin + LoadingMinutes, 0, plant, 35);
                break;
            case DeliveryStatus.InTransit:
                Stay(sinceMin + LoadingMinutes, sinceMin, plant, 35);
                var late = sinceMin > travel;
                Drive(sinceMin, 0, late ? 0.92 : Math.Min(0.92, (double)sinceMin / travel), late ? 20 : 0);
                break;
            case DeliveryStatus.ArrivedAtSite:
            case DeliveryStatus.Unloading:
                var atSite = sinceMin + (status == DeliveryStatus.Unloading ? UnloadedMinutes : 0);
                Stay(atSite + travel + LoadingMinutes, atSite + travel, plant, 35);
                Drive(atSite + travel, atSite, 1, 0);
                Stay(atSite, 0, site, 30);
                break;
            case DeliveryStatus.Delivered:
                var leftSite = sinceMin;
                Stay(leftSite + SiteMinutes + travel + LoadingMinutes, leftSite + SiteMinutes + travel, plant, 35);
                Drive(leftSite + SiteMinutes + travel, leftSite + SiteMinutes, 1, 0);
                Stay(leftSite + SiteMinutes, leftSite, site, 30);
                break;
        }

        return points.Select(p => new GpsPosition
        {
            Id = Guid.NewGuid(), CompanyId = companyId, ClientId = Guid.NewGuid(),
            TruckPlate = plate, DeliveryId = deliveryId,
            Latitude = p.Lat, Longitude = p.Lng, AccuracyM = 5 + rnd.NextDouble() * 10,
            SpeedKmh = Math.Round(p.Speed, 1),
            RecordedAt = now.AddMinutes(-p.MinutesAgo), ReceivedAt = now.AddMinutes(-p.MinutesAgo),
        });
    }

    // A point along a gently curved road from the plant to the site (f = 0..1)
    private static (double Lat, double Lng) Road((double Lat, double Lng) a, (double Lat, double Lng) b, double f, int seed)
    {
        // A curve through a control point pushed sideways from the middle
        var side = seed % 2 == 0 ? 1 : -1;
        var (mx, my) = ((a.Lat + b.Lat) / 2, (a.Lng + b.Lng) / 2);
        var (cx, cy) = (mx - (b.Lng - a.Lng) * 0.18 * side, my + (b.Lat - a.Lat) * 0.18 * side);
        var u = 1 - f;
        return (u * u * a.Lat + 2 * u * f * cx + f * f * b.Lat, u * u * a.Lng + 2 * u * f * cy + f * f * b.Lng);
    }

    // A point moved randomly by up to "metres" (GPS is never exactly still)
    private static (double Lat, double Lng) Jitter((double Lat, double Lng) p, double metres, Random rnd)
    {
        var dLat = (rnd.NextDouble() * 2 - 1) * metres / 111_320;
        var dLng = (rnd.NextDouble() * 2 - 1) * metres / (111_320 * Math.Cos(p.Lat * Math.PI / 180));
        return (p.Lat + dLat, p.Lng + dLng);
    }
}
