using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Queries;

// ============================================================================
// SCREEN 3 — Vehicles: trucks and trailers (docs/back-office-design.md).
// Read only: vehicles are master data, received from the client's other
// system. What TruckGo adds is the vehicle's STATE — calculated from its
// deliveries, never stored: idle, at the plant, on the road, at the ship-to.
// (The forwarding agent is shown as information on the vehicle; there is no
// separate screen for agents — decided 2026-10-11.)
// ============================================================================

/// <summary>Where a vehicle is in its work right now. Calculated, not stored.</summary>
public enum VehicleState
{
    /// <summary>No delivery under way.</summary>
    Idle,
    /// <summary>Its delivery is "at plant" or "loading".</summary>
    AtPlant,
    /// <summary>Its delivery is "in transit".</summary>
    OnTheRoad,
    /// <summary>Its delivery is "arrived at site" or "unloading".</summary>
    AtShipTo,
}

public static class VehicleStates
{
    /// <summary>The statuses of a delivery that has started and is not finished.</summary>
    public static readonly DeliveryStatus[] Underway =
    [
        DeliveryStatus.AtPlant, DeliveryStatus.Loading, DeliveryStatus.InTransit,
        DeliveryStatus.ArrivedAtSite, DeliveryStatus.Unloading,
    ];

    /// <summary>The vehicle's state while its delivery has this status.</summary>
    public static VehicleState From(DeliveryStatus status) => status switch
    {
        DeliveryStatus.AtPlant or DeliveryStatus.Loading => VehicleState.AtPlant,
        DeliveryStatus.InTransit => VehicleState.OnTheRoad,
        DeliveryStatus.ArrivedAtSite or DeliveryStatus.Unloading => VehicleState.AtShipTo,
        _ => VehicleState.Idle,
    };
}

/// <summary>The delivery a vehicle is working on now (null when idle).</summary>
public record CurrentDelivery(
    Guid DeliveryId,      // to open the delivery's page
    string PlantCode,
    string Number,
    string CustomerName,
    string ShipToName,
    string Material,
    DeliveryStatus Status,
    DateTime Since); // when the delivery last changed status

/// <summary>One line of the vehicle list.</summary>
public record VehicleRow(
    Guid Id,
    string Plate,
    VehicleKind Kind,
    string Model,
    string? Description,
    string? ForwardingAgentName,
    bool IsActive,
    DateTime LastReceivedAt,
    VehicleState State,
    CurrentDelivery? Current);

/// <summary>A delivery done (or planned) with the vehicle, for its page.</summary>
public record VehicleDeliveryRow(
    Guid DeliveryId,      // to open the delivery's page
    string PlantCode,
    string Number,
    DateTime ScheduledAt,
    string CustomerName,
    string ShipToName,
    string Material,
    double OrderedTons,
    string? TruckPlate,
    string? TrailerPlate,
    DeliveryStatus Status);

/// <summary>A vehicle's page: details, what it does now, recent deliveries.</summary>
public record VehicleDetail(
    Guid Id,
    string Code,
    string Plate,
    VehicleKind Kind,
    string Model,
    string? Description,
    string? ForwardingAgentCode,
    string? ForwardingAgentName,
    string? ForwardingAgentPhone,
    bool IsActive,
    DateTime LastReceivedAt,
    IReadOnlyDictionary<string, string> Extra,
    VehicleState State,
    CurrentDelivery? Current,
    IReadOnlyList<VehicleDeliveryRow> RecentDeliveries);

/// <summary>The reads behind the Vehicles screen, always inside ONE company.</summary>
public class VehicleQueries(IDbContextFactory<TruckGoDb> dbFactory)
{
    /// <summary>How many deliveries the vehicle page lists (newest first).</summary>
    public const int RecentDeliveryCount = 20;

    /// <summary>All trucks and trailers of the company, trucks first, by plate, with their state now.</summary>
    public async Task<List<VehicleRow>> ListAsync(Guid companyId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var vehicles = await db.Vehicles.AsNoTracking()
            .Include(v => v.ForwardingAgent)
            .Where(v => v.CompanyId == companyId)
            .ToListAsync();

        // Trucks first, then trailers. Sorted here, not in the database: the
        // kind is stored as text, and "Trailer" comes before "Truck" in A-Z
        vehicles = [.. vehicles.OrderBy(v => v.Kind).ThenBy(v => v.Plate)];

        // The deliveries under way right now — few at any moment, so read
        // them once and match them to the vehicles here
        var underway = await UnderwayAsync(db, companyId);

        return vehicles.Select(v =>
        {
            var current = CurrentFor(v.Plate, underway);
            return new VehicleRow(v.Id, v.Plate, v.Kind, v.Model, v.Description, v.ForwardingAgent?.Name,
                v.IsActive, v.LastReceivedAt,
                current is null ? VehicleState.Idle : VehicleStates.From(current.Status), current);
        }).ToList();
    }

    /// <summary>One vehicle with what it does now and its recent deliveries; null if not this company's.</summary>
    public async Task<VehicleDetail?> GetAsync(Guid companyId, Guid vehicleId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var v = await db.Vehicles.AsNoTracking()
            .Include(x => x.ForwardingAgent)
            .FirstOrDefaultAsync(x => x.Id == vehicleId && x.CompanyId == companyId);
        if (v is null) return null;

        var current = CurrentFor(v.Plate, await UnderwayAsync(db, companyId));

        // A truck appears on deliveries as the truck, a trailer as the trailer
        var recent = await db.Deliveries
            .Where(d => d.CompanyId == companyId && (d.TruckPlate == v.Plate || d.TrailerPlate == v.Plate))
            .OrderByDescending(d => d.ScheduledAt)
            .Take(RecentDeliveryCount)
            .Select(d => new VehicleDeliveryRow(d.Id, d.Plant.ExternalCode, d.Number, d.ScheduledAt, d.Customer.Name,
                d.ShipTo.Name, d.Material, d.OrderedTons, d.TruckPlate, d.TrailerPlate, d.Status))
            .ToListAsync();

        return new VehicleDetail(v.Id, v.ExternalCode, v.Plate, v.Kind, v.Model, v.Description,
            v.ForwardingAgent?.ExternalCode, v.ForwardingAgent?.Name, v.ForwardingAgent?.Phone,
            v.IsActive, v.LastReceivedAt, v.Extra,
            current is null ? VehicleState.Idle : VehicleStates.From(current.Status), current, recent);
    }

    // The company's deliveries that have started and are not finished, with
    // the plates they use
    private static async Task<List<(string? Truck, string? Trailer, CurrentDelivery Delivery)>> UnderwayAsync(
        TruckGoDb db, Guid companyId)
    {
        var rows = await db.Deliveries
            .Where(d => d.CompanyId == companyId && VehicleStates.Underway.Contains(d.Status))
            .Select(d => new
            {
                d.TruckPlate,
                d.TrailerPlate,
                Delivery = new CurrentDelivery(d.Id, d.Plant.ExternalCode, d.Number, d.Customer.Name, d.ShipTo.Name,
                    d.Material, d.Status, d.UpdatedAt),
            })
            .ToListAsync();
        return rows.Select(r => (r.TruckPlate, r.TrailerPlate, r.Delivery)).ToList();
    }

    // A vehicle normally has at most one delivery under way; if the data ever
    // says two, the most recently changed one counts
    private static CurrentDelivery? CurrentFor(string plate,
        List<(string? Truck, string? Trailer, CurrentDelivery Delivery)> underway) =>
        underway
            .Where(u => u.Truck == plate || u.Trailer == plate)
            .Select(u => u.Delivery)
            .MaxBy(d => d.Since);
}
