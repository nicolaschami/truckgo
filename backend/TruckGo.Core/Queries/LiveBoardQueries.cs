using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Queries;

// ============================================================================
// SCREEN 7 — Live board (docs/back-office-design.md).
// Where every truck is right now and which ones need attention. Built from
// the deliveries under way (their status comes from the app), the company's
// warning limits (Settings), and today's deliveries. Nothing here is stored:
// everything is calculated at each refresh.
// ============================================================================

/// <summary>How much attention a card needs.</summary>
public enum Attention
{
    /// <summary>All fine.</summary>
    None,
    /// <summary>Past the Settings limit — orange.</summary>
    Warning,
    /// <summary>Twice the limit, or late for the delivery window — red.</summary>
    Danger,
}

/// <summary>One truck at work, as a card on the board.</summary>
public record BoardCard(
    Guid DeliveryId,      // to open the delivery's page
    string? TruckPlate,
    string? TrailerPlate,
    Guid? TruckId,          // to open the vehicle page
    string PlantCode,
    string Number,
    string CustomerName,
    string ShipToName,
    string Material,
    double OrderedTons,
    DeliveryStatus Status,
    VehicleState Column,    // the board column: at plant / on the road / at ship-to
    DateTime Since,         // when the delivery last changed status (the arrival time until status events are stored)
    double Minutes,         // how long in this state, at the moment of the refresh
    int? LimitMinutes,      // the Settings limit for this column (null on the road)
    DateTime WindowStart,
    DateTime WindowEnd,
    Attention Attention,
    string? Reason);        // why it needs attention, in words

/// <summary>An active truck with no delivery under way, and its next delivery today (if any).</summary>
public record IdleTruck(
    Guid Id,
    string Plate,
    string Model,
    string? NextNumber,
    string? NextPlantCode,
    DateTime? NextScheduledAt,
    string? NextShipToName);

/// <summary>The numbers at the top of the board.</summary>
public record BoardTotals(
    int Working,
    int AtPlant,
    int OnTheRoad,
    int AtShipTo,
    int Idle,
    int DeliveredToday,
    double DeliveredTonsToday,  // net weight (2nd - 1st) where both weights exist, else the ordered tonnes
    int Warnings);              // cards needing attention (orange or red)

/// <summary>A plant, for the board's plant filter.</summary>
public record BoardPlant(Guid Id, string Code, string Name);

/// <summary>Everything the live board shows, at one moment.</summary>
public record LiveBoard(
    DateTime At,
    IReadOnlyList<BoardCard> Cards,
    IReadOnlyList<IdleTruck> Idle,
    BoardTotals Totals,
    IReadOnlyList<BoardPlant> Plants);

/// <summary>The reads and rules behind the live board, always inside ONE company.</summary>
public class LiveBoardQueries(IDbContextFactory<TruckGoDb> dbFactory)
{
    /// <summary>
    /// The board right now. <paramref name="plantId"/> null = all plants.
    /// "Today" is given as a UTC range by the caller (the screen knows the
    /// local day); <paramref name="now"/> is the moment the board is drawn for.
    /// </summary>
    public async Task<LiveBoard> GetAsync(Guid companyId, Guid? plantId, DateTime todayFromUtc, DateTime todayToUtc, DateTime now)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var settings = await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.CompanyId == companyId)
            ?? new CompanySettings();

        var plants = await db.Plants
            .Where(p => p.CompanyId == companyId && p.IsActive)
            .OrderBy(p => p.ExternalCode)
            .Select(p => new BoardPlant(p.Id, p.ExternalCode, p.Name))
            .ToListAsync();

        var deliveries = db.Deliveries.Where(d => d.CompanyId == companyId);
        if (plantId is { } onlyPlant) deliveries = deliveries.Where(d => d.PlantId == onlyPlant);

        // Trucks of the company, to link cards to the vehicle pages and list the idle ones
        var trucks = await db.Vehicles
            .Where(v => v.CompanyId == companyId && v.Kind == VehicleKind.Truck && v.IsActive)
            .Select(v => new { v.Id, v.Plate, v.Model })
            .ToListAsync();
        var truckIds = trucks.ToDictionary(t => t.Plate, t => t.Id);

        // ---- The cards: every delivery under way ----
        var underway = await deliveries
            .Where(d => VehicleStates.Underway.Contains(d.Status))
            .Select(d => new
            {
                d.Id, d.TruckPlate, d.TrailerPlate, PlantCode = d.Plant.ExternalCode, d.Number,
                CustomerName = d.Customer.Name, ShipToName = d.ShipTo.Name, d.Material, d.OrderedTons,
                d.Status, d.UpdatedAt, d.WindowStart, d.WindowEnd,
            })
            .ToListAsync();

        var cards = underway.Select(d =>
            {
                var column = VehicleStates.From(d.Status);
                var minutes = Math.Max(0, (now - d.UpdatedAt).TotalMinutes);
                int? limit = column switch
                {
                    VehicleState.AtPlant => settings.LongWaitAtPlantMinutes,
                    VehicleState.AtShipTo => settings.LongWaitAtShipToMinutes,
                    _ => null,
                };
                var (attention, reason) = Judge(column, minutes, limit, d.WindowEnd, now, settings.WindowToleranceMinutes);
                return new BoardCard(d.Id, d.TruckPlate, d.TrailerPlate,
                    d.TruckPlate is { } p && truckIds.TryGetValue(p, out var id) ? id : null,
                    d.PlantCode, d.Number, d.CustomerName, d.ShipToName, d.Material, d.OrderedTons,
                    d.Status, column, d.UpdatedAt, minutes, limit, d.WindowStart, d.WindowEnd, attention, reason);
            })
            // In each column: the ones needing attention first, then the longest waiting
            .OrderByDescending(c => c.Attention).ThenByDescending(c => c.Minutes)
            .ToList();

        // ---- The idle trucks, with their next delivery today ----
        var busy = underway.Select(d => d.TruckPlate).OfType<string>().ToHashSet();
        var nextToday = await deliveries
            .Where(d => d.Status == DeliveryStatus.Assigned && d.TruckPlate != null
                && d.ScheduledAt >= todayFromUtc && d.ScheduledAt < todayToUtc)
            .Select(d => new { d.TruckPlate, d.Number, PlantCode = d.Plant.ExternalCode, d.ScheduledAt, ShipToName = d.ShipTo.Name })
            .ToListAsync();
        var idle = trucks
            .Where(t => !busy.Contains(t.Plate))
            .Select(t =>
            {
                // The earliest planned delivery still to start, if any
                var next = nextToday.Where(n => n.TruckPlate == t.Plate).MinBy(n => n.ScheduledAt);
                return new IdleTruck(t.Id, t.Plate, t.Model, next?.Number, next?.PlantCode, next?.ScheduledAt, next?.ShipToName);
            })
            // Trucks with a delivery coming first (soonest first), then the free ones
            .OrderBy(t => t.NextScheduledAt is null).ThenBy(t => t.NextScheduledAt).ThenBy(t => t.Plate)
            .ToList();
        // With a plant filter, only idle trucks that have something planned at that plant
        if (plantId is not null) idle = idle.Where(t => t.NextNumber is not null).ToList();

        // ---- Delivered today (planned for today, now delivered), with the net
        // weight where both weighings exist ----
        var delivered = await deliveries
            .Where(d => d.Status == DeliveryStatus.Delivered && d.ScheduledAt >= todayFromUtc && d.ScheduledAt < todayToUtc)
            .Select(d => new { d.OrderedTons, Weighings = d.Weighings.Select(w => new { w.Kind, w.Tons, w.WeighedAt }).ToList() })
            .ToListAsync();
        double NetOrOrdered(double ordered, IEnumerable<(WeighingKind Kind, double Tons, DateTime At)> w)
        {
            var first = w.Where(x => x.Kind == WeighingKind.First).MaxBy(x => x.At);
            var second = w.Where(x => x.Kind == WeighingKind.Second).MaxBy(x => x.At);
            return first != default && second != default ? second.Tons - first.Tons : ordered;
        }
        var deliveredTons = delivered.Sum(d => NetOrOrdered(d.OrderedTons, d.Weighings.Select(w => (w.Kind, w.Tons, w.WeighedAt))));

        var totals = new BoardTotals(
            Working: cards.Count,
            AtPlant: cards.Count(c => c.Column == VehicleState.AtPlant),
            OnTheRoad: cards.Count(c => c.Column == VehicleState.OnTheRoad),
            AtShipTo: cards.Count(c => c.Column == VehicleState.AtShipTo),
            Idle: idle.Count,
            DeliveredToday: delivered.Count,
            DeliveredTonsToday: Math.Round(deliveredTons, 1),
            Warnings: cards.Count(c => c.Attention != Attention.None));

        return new LiveBoard(now, cards, idle, totals, plants);
    }

    /// <summary>
    /// The warning rules (docs/back-office-design.md, section 4):
    /// waiting at the plant or the ship-to longer than the Settings limit =
    /// orange, twice the limit = red; on the road past the end of the
    /// delivery window (plus the tolerance) = red "late".
    /// </summary>
    public static (Attention, string?) Judge(VehicleState column, double minutes, int? limitMinutes,
        DateTime windowEnd, DateTime now, int toleranceMinutes)
    {
        if (column == VehicleState.OnTheRoad)
        {
            var lateBy = (now - windowEnd).TotalMinutes - toleranceMinutes;
            return lateBy > 0
                ? (Attention.Danger, $"Late — the delivery window closed {Minutes(lateBy + toleranceMinutes)} ago")
                : (Attention.None, null);
        }

        if (limitMinutes is not { } limit) return (Attention.None, null);
        var where = column == VehicleState.AtPlant ? "at the plant" : "at the ship-to";
        if (minutes >= 2 * limit) return (Attention.Danger, $"Waiting {where} for {Minutes(minutes)} — over twice the {limit} min limit");
        if (minutes >= limit) return (Attention.Warning, $"Waiting {where} for {Minutes(minutes)} — over the {limit} min limit");
        return (Attention.None, null);
    }

    private static string Minutes(double m) => m < 60 ? $"{(int)m} min" : $"{(int)(m / 60)} h {(int)m % 60:00}";
}
