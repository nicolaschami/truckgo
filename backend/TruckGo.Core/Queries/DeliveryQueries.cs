using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Queries;

// ============================================================================
// SCREEN 6 — Deliveries (docs/back-office-design.md).
// Follow each delivery from the plant to the customer. Deliveries are master
// data (planned by the client's system); their status comes from the app.
// Still to come with backend phase 2: the status timeline and durations,
// the driver, and the proof of delivery — the screen says so.
// ============================================================================

/// <summary>One line of the delivery list.</summary>
public record DeliveryRow(
    Guid Id,
    string PlantCode,
    string Number,
    string OrderNumber,
    string CustomerName,
    string ShipToName,
    string Material,
    double OrderedTons,
    double? NetTons,          // 2nd weight - 1st weight, when both exist
    string? TruckPlate,
    string? TrailerPlate,
    DateTime ScheduledAt,
    DateTime WindowStart,
    DateTime WindowEnd,
    DeliveryStatus Status,
    DateTime UpdatedAt,
    Attention Attention,      // the live board's rules, for deliveries under way
    string? Reason);

/// <summary>A weighbridge reading, as listed on the delivery page.</summary>
public record WeighingRow(WeighingKind Kind, double Tons, DateTime WeighedAt, string? TicketNumber, string? Weighbridge);

/// <summary>A delivery's page: everything TruckGo knows about it today.</summary>
public record DeliveryDetail(
    Guid Id,
    string Number,
    string OrderNumber,
    DeliveryStatus Status,
    Attention Attention,
    string? Reason,
    DateTime ScheduledAt,
    DateTime WindowStart,
    DateTime WindowEnd,
    DateTime UpdatedAt,
    DateTime LastReceivedAt,
    // From where
    Guid PlantId, string PlantCode, string PlantName, double PlantLatitude, double PlantLongitude,
    // To whom
    Guid CustomerId, string CustomerCode, string CustomerName,
    Guid ShipToId, string ShipToCode, string ShipToName, string? ShipToAddress, string? ShipToCity,
    double ShipToLatitude, double ShipToLongitude,
    string? ContactName, string? ContactPhone, string? DeliveryInstructions,
    // What and with what
    string Material,
    double OrderedTons,
    double DistanceKm,
    string? Notes,
    string? TruckPlate, Guid? TruckId,
    string? TrailerPlate, Guid? TrailerId,
    // The weighbridge
    IReadOnlyList<WeighingRow> Weighings,   // all readings, oldest first (re-weighs included)
    double? TareTons,                       // latest 1st weight
    double? GrossTons,                      // latest 2nd weight
    double? NetTons,                        // gross - tare
    IReadOnlyDictionary<string, string> Extra,
    double GeofenceRadiusM);

/// <summary>The reads behind the Deliveries screen, always inside ONE company.</summary>
public class DeliveryQueries(IDbContextFactory<TruckGoDb> dbFactory)
{
    /// <summary>
    /// The deliveries planned in a time range (the chosen day, as UTC),
    /// optionally for one plant, by planned time. Status and search filters
    /// are applied on the screen (a day's deliveries are few).
    /// </summary>
    public async Task<List<DeliveryRow>> ListAsync(Guid companyId, DateTime fromUtc, DateTime toUtc, Guid? plantId, DateTime now)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var settings = await SettingsAsync(db, companyId);

        var query = db.Deliveries.Where(d => d.CompanyId == companyId && d.ScheduledAt >= fromUtc && d.ScheduledAt < toUtc);
        if (plantId is { } p) query = query.Where(d => d.PlantId == p);

        var rows = await query
            .OrderBy(d => d.ScheduledAt)
            .Select(d => new
            {
                d.Id, PlantCode = d.Plant.ExternalCode, d.Number, d.OrderNumber, CustomerName = d.Customer.Name,
                ShipToName = d.ShipTo.Name, d.Material, d.OrderedTons, d.TruckPlate, d.TrailerPlate,
                d.ScheduledAt, d.WindowStart, d.WindowEnd, d.Status, d.UpdatedAt,
                Weighings = d.Weighings.Select(w => new { w.Kind, w.Tons, w.WeighedAt }).ToList(),
            })
            .ToListAsync();

        return rows.Select(d =>
        {
            var (attention, reason) = AttentionOf(d.Status, d.UpdatedAt, d.WindowEnd, now, settings);
            return new DeliveryRow(d.Id, d.PlantCode, d.Number, d.OrderNumber, d.CustomerName, d.ShipToName,
                d.Material, d.OrderedTons,
                Net(d.Weighings.Select(w => new WeighingRow(w.Kind, w.Tons, w.WeighedAt, null, null))),
                d.TruckPlate, d.TrailerPlate, d.ScheduledAt, d.WindowStart, d.WindowEnd, d.Status, d.UpdatedAt,
                attention, reason);
        }).ToList();
    }

    /// <summary>One delivery with everything around it; null if it is not this company's.</summary>
    public async Task<DeliveryDetail?> GetAsync(Guid companyId, Guid deliveryId, DateTime now)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var d = await db.Deliveries.AsNoTracking()
            .Include(x => x.Plant).Include(x => x.Customer).Include(x => x.ShipTo).Include(x => x.Weighings)
            .FirstOrDefaultAsync(x => x.Id == deliveryId && x.CompanyId == companyId);
        if (d is null) return null;

        var settings = await SettingsAsync(db, companyId);

        // The vehicles by plate, to link to their pages (the delivery keeps plates, not links)
        var plates = new[] { d.TruckPlate, d.TrailerPlate }.OfType<string>().ToList();
        var vehicles = await db.Vehicles
            .Where(v => v.CompanyId == companyId && plates.Contains(v.Plate))
            .Select(v => new { v.Plate, v.Id })
            .ToDictionaryAsync(v => v.Plate, v => v.Id);
        Guid? IdOf(string? plate) => plate is not null && vehicles.TryGetValue(plate, out var id) ? id : null;

        var weighings = d.Weighings
            .OrderBy(w => w.WeighedAt)
            .Select(w => new WeighingRow(w.Kind, w.Tons, w.WeighedAt, w.TicketNumber, w.Weighbridge))
            .ToList();
        var tare = weighings.Where(w => w.Kind == WeighingKind.First).MaxBy(w => w.WeighedAt);
        var gross = weighings.Where(w => w.Kind == WeighingKind.Second).MaxBy(w => w.WeighedAt);

        var (attention, reason) = AttentionOf(d.Status, d.UpdatedAt, d.WindowEnd, now, settings);
        var s = d.ShipTo;
        return new DeliveryDetail(d.Id, d.Number, d.OrderNumber, d.Status, attention, reason,
            d.ScheduledAt, d.WindowStart, d.WindowEnd, d.UpdatedAt, d.LastReceivedAt,
            d.Plant.Id, d.Plant.ExternalCode, d.Plant.Name, d.Plant.Latitude, d.Plant.Longitude,
            d.Customer.Id, d.Customer.ExternalCode, d.Customer.Name,
            s.Id, s.ExternalCode, s.Name, s.Address, s.City, s.Latitude, s.Longitude,
            s.ContactName, s.ContactPhone, s.DeliveryInstructions,
            d.Material, d.OrderedTons, d.DistanceKm, d.Notes,
            d.TruckPlate, IdOf(d.TruckPlate), d.TrailerPlate, IdOf(d.TrailerPlate),
            weighings, tare?.Tons, gross?.Tons, Net(weighings),
            d.Extra, settings.GeofenceRadiusM);
    }

    // The latest 2nd weight minus the latest 1st weight, when both exist
    private static double? Net(IEnumerable<WeighingRow> weighings)
    {
        var list = weighings.ToList();
        var tare = list.Where(w => w.Kind == WeighingKind.First).MaxBy(w => w.WeighedAt);
        var gross = list.Where(w => w.Kind == WeighingKind.Second).MaxBy(w => w.WeighedAt);
        return tare is not null && gross is not null ? Math.Round(gross.Tons - tare.Tons, 3) : null;
    }

    // The live board's warning rules, for a delivery under way (none otherwise)
    private static (Attention, string?) AttentionOf(DeliveryStatus status, DateTime since, DateTime windowEnd,
        DateTime now, CompanySettings settings)
    {
        if (!VehicleStates.Underway.Contains(status)) return (Attention.None, null);
        var column = VehicleStates.From(status);
        int? limit = column switch
        {
            VehicleState.AtPlant => settings.LongWaitAtPlantMinutes,
            VehicleState.AtShipTo => settings.LongWaitAtShipToMinutes,
            _ => null,
        };
        return LiveBoardQueries.Judge(column, Math.Max(0, (now - since).TotalMinutes), limit, windowEnd, now, settings.WindowToleranceMinutes);
    }

    private static async Task<CompanySettings> SettingsAsync(TruckGoDb db, Guid companyId) =>
        await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.CompanyId == companyId) ?? new CompanySettings();
}
