using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Queries;

// ============================================================================
// SCREEN 8 — Map & trace (docs/back-office-design.md).
// LIVE: every truck at its last GPS point, coloured by its state.
// TRACE: the route of one delivery, or of one truck for a day, with the
// stops (standing still longer than the Settings limit, outside the plant
// and site geofences) and the points for the replay slider.
// The points come from the driver app (POST /api/v1/positions).
// ============================================================================

/// <summary>A plant or a ship-to on the map, with the page it opens.</summary>
public record MapPlace(string Kind, string Label, double Latitude, double Longitude, string Url);

/// <summary>A truck on the live map: its last point, its state and its delivery.</summary>
public record LiveTruck(
    Guid? VehicleId,
    string Plate,
    double Latitude,
    double Longitude,
    DateTime At,              // when the phone took the point
    double? SpeedKmh,
    VehicleState State,
    Guid? DeliveryId,
    string? DeliveryLabel,    // "QN2 / 900103 → Station Car Park"
    bool Stale);              // no news for a while: shown faded

/// <summary>Everything the live map shows.</summary>
public record LiveMap(DateTime At, IReadOnlyList<LiveTruck> Trucks, IReadOnlyList<MapPlace> Places, double GeofenceRadiusM);

/// <summary>One point of a route.</summary>
public record TracePoint(double Latitude, double Longitude, DateTime At, double? SpeedKmh);

/// <summary>A place where the truck stood still longer than the Settings limit.</summary>
public record TraceStop(double Latitude, double Longitude, DateTime From, DateTime To)
{
    public double Minutes => (To - From).TotalMinutes;
}

/// <summary>A route to draw and replay.</summary>
public record Trace(
    string Title,
    string Subtitle,
    string? TruckPlate,
    Guid? DeliveryId,
    IReadOnlyList<TracePoint> Points,
    IReadOnlyList<TraceStop> Stops,
    IReadOnlyList<MapPlace> Places,
    double DistanceKm,
    double GeofenceRadiusM,
    int LongStopMinutes);

/// <summary>The reads behind Map & trace, always inside ONE company.</summary>
public class MapQueries(IDbContextFactory<TruckGoDb> dbFactory)
{
    /// <summary>The live map shows trucks heard from in this many hours.</summary>
    public const int LiveHours = 12;

    /// <summary>A last point older than this (minutes) is shown faded: no news.</summary>
    public const int StaleMinutes = 30;

    /// <summary>Two points closer than this (metres) count as "standing still".</summary>
    public const double StillRadiusM = 60;

    // ------------------------------------------------------------------
    // LIVE
    // ------------------------------------------------------------------

    public async Task<LiveMap> LiveAsync(Guid companyId, DateTime now)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var settings = await SettingsAsync(db, companyId);
        var since = now.AddHours(-LiveHours);

        // The last point of each truck (one row per plate)
        var last = await db.Positions
            .Where(p => p.CompanyId == companyId && p.RecordedAt >= since)
            .GroupBy(p => p.TruckPlate)
            .Select(g => g.OrderByDescending(p => p.RecordedAt).First())
            .ToListAsync();

        // What each truck is doing (its delivery under way, if any)
        var underway = await db.Deliveries
            .Where(d => d.CompanyId == companyId && VehicleStates.Underway.Contains(d.Status) && d.TruckPlate != null)
            .Select(d => new
            {
                d.Id, d.TruckPlate, d.Status, d.UpdatedAt, PlantCode = d.Plant.ExternalCode, d.Number,
                ShipToId = d.ShipTo.Id, ShipToName = d.ShipTo.Name, d.ShipTo.Latitude, d.ShipTo.Longitude,
            })
            .ToListAsync();
        var byPlate = underway.GroupBy(d => d.TruckPlate!).ToDictionary(g => g.Key, g => g.MaxBy(d => d.UpdatedAt)!);

        var vehicleIds = await db.Vehicles.Where(v => v.CompanyId == companyId)
            .Select(v => new { v.Plate, v.Id }).ToDictionaryAsync(v => v.Plate, v => v.Id);

        var trucks = last
            .Select(p =>
            {
                byPlate.TryGetValue(p.TruckPlate, out var d);
                return new LiveTruck(
                    vehicleIds.TryGetValue(p.TruckPlate, out var vid) ? vid : null,
                    p.TruckPlate, p.Latitude, p.Longitude, p.RecordedAt, p.SpeedKmh,
                    d is null ? VehicleState.Idle : VehicleStates.From(d.Status),
                    d?.Id, d is null ? null : $"{d.PlantCode} / {d.Number} → {d.ShipToName}",
                    (now - p.RecordedAt).TotalMinutes > StaleMinutes);
            })
            .OrderBy(t => t.State == VehicleState.Idle).ThenBy(t => t.Plate)
            .ToList();

        // The plants, and the sites trucks are heading to or at
        var places = await db.Plants.Where(p => p.CompanyId == companyId && p.IsActive)
            .Select(p => new MapPlace("plant", p.ExternalCode + " · " + p.Name, p.Latitude, p.Longitude, "/plants/" + p.Id))
            .ToListAsync();
        places.AddRange(underway.DistinctBy(d => d.ShipToId)
            .Select(d => new MapPlace("site", d.ShipToName, d.Latitude, d.Longitude, "/customers/ship-tos/" + d.ShipToId)));

        return new LiveMap(now, trucks, places, settings.GeofenceRadiusM);
    }

    // ------------------------------------------------------------------
    // TRACE
    // ------------------------------------------------------------------

    /// <summary>The route of one delivery (the points the app sent while working on it).</summary>
    public async Task<Trace?> DeliveryTraceAsync(Guid companyId, Guid deliveryId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var d = await db.Deliveries.AsNoTracking()
            .Include(x => x.Plant).Include(x => x.Customer).Include(x => x.ShipTo)
            .FirstOrDefaultAsync(x => x.Id == deliveryId && x.CompanyId == companyId);
        if (d is null) return null;

        var points = await db.Positions
            .Where(p => p.DeliveryId == d.Id)
            .OrderBy(p => p.RecordedAt)
            .Select(p => new TracePoint(p.Latitude, p.Longitude, p.RecordedAt, p.SpeedKmh))
            .ToListAsync();

        MapPlace[] places =
        [
            new("plant", d.Plant.ExternalCode + " · " + d.Plant.Name, d.Plant.Latitude, d.Plant.Longitude, "/plants/" + d.Plant.Id),
            new("site", d.ShipTo.Name, d.ShipTo.Latitude, d.ShipTo.Longitude, "/customers/ship-tos/" + d.ShipTo.Id),
        ];
        return await BuildAsync(db, companyId, $"{d.Plant.ExternalCode} / {d.Number}",
            $"{d.Customer.Name} → {d.ShipTo.Name}", d.TruckPlate, d.Id, points, places);
    }

    /// <summary>The route of one truck over a time range (a day, as UTC).</summary>
    public async Task<Trace> TruckTraceAsync(Guid companyId, string plate, DateTime fromUtc, DateTime toUtc)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var points = await db.Positions
            .Where(p => p.CompanyId == companyId && p.TruckPlate == plate && p.RecordedAt >= fromUtc && p.RecordedAt < toUtc)
            .OrderBy(p => p.RecordedAt)
            .Select(p => new TracePoint(p.Latitude, p.Longitude, p.RecordedAt, p.SpeedKmh))
            .ToListAsync();

        // The plants and sites of the truck's deliveries that day
        var stops = await db.Deliveries
            .Where(d => d.CompanyId == companyId && d.TruckPlate == plate && d.ScheduledAt >= fromUtc.AddHours(-12) && d.ScheduledAt < toUtc.AddHours(12))
            .Select(d => new
            {
                PlantId = d.Plant.Id, PlantLabel = d.Plant.ExternalCode + " · " + d.Plant.Name, PLat = d.Plant.Latitude, PLng = d.Plant.Longitude,
                SiteId = d.ShipTo.Id, SiteLabel = d.ShipTo.Name, SLat = d.ShipTo.Latitude, SLng = d.ShipTo.Longitude,
            })
            .ToListAsync();
        var places = stops.DistinctBy(s => s.PlantId).Select(s => new MapPlace("plant", s.PlantLabel, s.PLat, s.PLng, "/plants/" + s.PlantId))
            .Concat(stops.DistinctBy(s => s.SiteId).Select(s => new MapPlace("site", s.SiteLabel, s.SLat, s.SLng, "/customers/ship-tos/" + s.SiteId)))
            .ToList();

        return await BuildAsync(db, companyId, plate, "The truck's route over the day", plate, null, points, places);
    }

    private static async Task<Trace> BuildAsync(TruckGoDb db, Guid companyId, string title, string subtitle,
        string? plate, Guid? deliveryId, List<TracePoint> points, IReadOnlyList<MapPlace> places)
    {
        var settings = await SettingsAsync(db, companyId);
        var stops = FindStops(points, settings.LongStopMinutes, places, settings.GeofenceRadiusM);
        var km = points.Zip(points.Skip(1)).Sum(p => Geo.DistanceM(p.First.Latitude, p.First.Longitude, p.Second.Latitude, p.Second.Longitude)) / 1000;
        return new Trace(title, subtitle, plate, deliveryId, points, stops, places, Math.Round(km, 1),
            settings.GeofenceRadiusM, settings.LongStopMinutes);
    }

    /// <summary>
    /// The unexpected stops of a route: the truck stayed within
    /// <see cref="StillRadiusM"/> of one place for at least
    /// <paramref name="longStopMinutes"/>, and that place is outside every
    /// plant and site geofence (waiting there is normal, and shown elsewhere).
    /// </summary>
    public static List<TraceStop> FindStops(IReadOnlyList<TracePoint> points, int longStopMinutes,
        IReadOnlyList<MapPlace> places, double geofenceRadiusM)
    {
        var stops = new List<TraceStop>();
        var i = 0;
        while (i < points.Count)
        {
            // Grow a group of points that stay close to the first one
            var j = i;
            while (j + 1 < points.Count &&
                   Geo.DistanceM(points[i].Latitude, points[i].Longitude, points[j + 1].Latitude, points[j + 1].Longitude) <= StillRadiusM)
                j++;

            var minutes = (points[j].At - points[i].At).TotalMinutes;
            var insideAPlace = places.Any(p => Geo.DistanceM(points[i].Latitude, points[i].Longitude, p.Latitude, p.Longitude) <= geofenceRadiusM);
            if (minutes >= longStopMinutes && !insideAPlace)
                stops.Add(new TraceStop(points[i].Latitude, points[i].Longitude, points[i].At, points[j].At));

            i = j + 1;
        }
        return stops;
    }

    private static async Task<CompanySettings> SettingsAsync(TruckGoDb db, Guid companyId) =>
        await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.CompanyId == companyId) ?? new CompanySettings();
}

/// <summary>Small distance helper (no map library needed on the server).</summary>
public static class Geo
{
    /// <summary>Distance in metres between two GPS points (haversine formula).</summary>
    public static double DistanceM(double lat1, double lng1, double lat2, double lng2)
    {
        const double earthRadiusM = 6_371_000;
        static double Rad(double deg) => deg * Math.PI / 180;
        var dLat = Rad(lat2 - lat1);
        var dLng = Rad(lng2 - lng1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
              + Math.Cos(Rad(lat1)) * Math.Cos(Rad(lat2)) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * earthRadiusM * Math.Asin(Math.Sqrt(a));
    }
}
