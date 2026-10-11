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
        }
        await db.SaveChangesAsync();
    }
}
