using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Queries;

// ============================================================================
// SCREEN 2 — Plants (docs/back-office-design.md).
// Read only: plants are master data, received from the client's other
// system. What TruckGo adds is what is happening there: which trucks are at
// the plant now, and today's deliveries from it.
// ============================================================================

/// <summary>One line of the plant list (and one dot on its map).</summary>
public record PlantRow(
    Guid Id,
    string Code,
    string Name,
    string? City,
    string? Country,
    double Latitude,
    double Longitude,
    bool IsActive,
    DateTime LastReceivedAt,
    int TrucksAtPlant,     // deliveries now "at plant" or "loading" here
    int DeliveriesToday);  // deliveries planned from here today

/// <summary>
/// A truck at the plant right now, with the delivery it is loading for.
/// <paramref name="Since"/> is when its delivery last changed status — the
/// arrival time until the app's status events are stored (backend phase 2).
/// </summary>
public record AtPlantRow(
    Guid DeliveryId,      // to open the delivery's page
    string? TruckPlate,
    string? TrailerPlate,
    string Number,
    string CustomerName,
    string ShipToName,
    string Material,
    DeliveryStatus Status,
    DateTime Since);

/// <summary>A delivery planned from the plant today.</summary>
public record PlantDeliveryRow(
    Guid DeliveryId,      // to open the delivery's page
    string Number,
    DateTime ScheduledAt,
    string CustomerName,
    string ShipToName,
    string Material,
    double OrderedTons,
    string? TruckPlate,
    DeliveryStatus Status);

/// <summary>A plant's page: details, who is there now, and today's deliveries.</summary>
public record PlantDetail(
    Guid Id,
    string Code,
    string Name,
    string? Address,
    string? City,
    string? Postcode,
    string? Country,
    string? Phone,
    double Latitude,
    double Longitude,
    bool IsActive,
    DateTime LastReceivedAt,
    IReadOnlyDictionary<string, string> Extra,
    IReadOnlyList<AtPlantRow> AtPlantNow,
    IReadOnlyList<PlantDeliveryRow> Today,
    double GeofenceRadiusM,
    int LongWaitMinutes);   // the "long wait at the plant" warning limit (Settings)

/// <summary>
/// The reads behind screen 2, always inside ONE company. "Today" is given by
/// the caller as a UTC time range (the screen knows the local day), so the
/// queries stay simple and testable.
/// </summary>
public class PlantQueries(IDbContextFactory<TruckGoDb> dbFactory)
{
    /// <summary>The statuses that mean "the truck is at the plant".</summary>
    public static readonly DeliveryStatus[] AtPlant = [DeliveryStatus.AtPlant, DeliveryStatus.Loading];

    /// <summary>All plants of the company, by name, with what is happening there.</summary>
    public async Task<List<PlantRow>> ListAsync(Guid companyId, DateTime todayFromUtc, DateTime todayToUtc)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Plants
            .Where(p => p.CompanyId == companyId)
            .OrderBy(p => p.Name)
            .Select(p => new PlantRow(p.Id, p.ExternalCode, p.Name, p.City, p.Country, p.Latitude, p.Longitude,
                p.IsActive, p.LastReceivedAt,
                // Counted by the database, one small sub-query each
                db.Deliveries.Count(d => d.PlantId == p.Id && AtPlant.Contains(d.Status)),
                db.Deliveries.Count(d => d.PlantId == p.Id && d.ScheduledAt >= todayFromUtc && d.ScheduledAt < todayToUtc)))
            .ToListAsync();
    }

    /// <summary>One plant with who is there now and today's deliveries; null if not this company's.</summary>
    public async Task<PlantDetail?> GetAsync(Guid companyId, Guid plantId, DateTime todayFromUtc, DateTime todayToUtc)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var p = await db.Plants.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == plantId && x.CompanyId == companyId);
        if (p is null) return null;

        // Longest waiting first: those are the ones to look at
        var atPlant = await db.Deliveries
            .Where(d => d.PlantId == p.Id && AtPlant.Contains(d.Status))
            .OrderBy(d => d.UpdatedAt)
            .Select(d => new AtPlantRow(d.Id, d.TruckPlate, d.TrailerPlate, d.Number, d.Customer.Name, d.ShipTo.Name,
                d.Material, d.Status, d.UpdatedAt))
            .ToListAsync();

        var today = await db.Deliveries
            .Where(d => d.PlantId == p.Id && d.ScheduledAt >= todayFromUtc && d.ScheduledAt < todayToUtc)
            .OrderBy(d => d.ScheduledAt)
            .Select(d => new PlantDeliveryRow(d.Id, d.Number, d.ScheduledAt, d.Customer.Name, d.ShipTo.Name,
                d.Material, d.OrderedTons, d.TruckPlate, d.Status))
            .ToListAsync();

        // TruckGo settings: the geofence radius and the waiting-time warning limit
        var settings = await db.Settings.AsNoTracking().FirstOrDefaultAsync(x => x.CompanyId == companyId)
            ?? new CompanySettings();

        return new PlantDetail(p.Id, p.ExternalCode, p.Name, p.Address, p.City, p.Postcode, p.Country, p.Phone,
            p.Latitude, p.Longitude, p.IsActive, p.LastReceivedAt, p.Extra, atPlant, today,
            settings.GeofenceRadiusM, settings.LongWaitAtPlantMinutes);
    }
}
