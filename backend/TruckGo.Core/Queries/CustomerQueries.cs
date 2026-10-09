using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Queries;

// ============================================================================
// SCREEN 1 — Customers → ship-tos (docs/back-office-design.md).
// Read only: customers and ship-tos are master data, received from the
// client's other system; TruckGo never changes them. These records are what
// the screens show — never the database rows themselves.
// ============================================================================

/// <summary>One line of the customer list.</summary>
public record CustomerRow(
    Guid Id,
    string Code,
    string Name,
    string? City,
    string? Country,
    int ShipToCount,
    bool IsActive,
    DateTime LastReceivedAt);

/// <summary>One ship-to, as listed on its customer's page and drawn on the map.</summary>
public record ShipToRow(
    Guid Id,
    string Code,
    string Name,
    string? Address,
    string? City,
    double Latitude,
    double Longitude,
    string? ContactName,
    string? ContactPhone,
    bool IsActive);

/// <summary>A customer's page: its details and its ship-tos.</summary>
public record CustomerDetail(
    Guid Id,
    string Code,
    string Name,
    string? Address,
    string? City,
    string? Postcode,
    string? Country,
    string? Phone,
    string? TaxId,
    bool IsActive,
    DateTime LastReceivedAt,
    IReadOnlyDictionary<string, string> Extra,
    IReadOnlyList<ShipToRow> ShipTos,
    double GeofenceRadiusM);

/// <summary>A delivery to a ship-to, for its "recent deliveries" list.</summary>
public record ShipToDeliveryRow(
    string PlantCode,
    string Number,
    DateTime ScheduledAt,
    string Material,
    double OrderedTons,
    string? TruckPlate,
    DeliveryStatus Status);

/// <summary>A ship-to's page: details, its customer, and recent deliveries.</summary>
public record ShipToDetail(
    Guid Id,
    string Code,
    string Name,
    Guid CustomerId,
    string CustomerCode,
    string CustomerName,
    string? Address,
    string? City,
    string? Postcode,
    string? Country,
    double Latitude,
    double Longitude,
    string? ContactName,
    string? ContactPhone,
    string? DeliveryInstructions,
    string? OpeningHours,
    bool IsActive,
    DateTime LastReceivedAt,
    IReadOnlyDictionary<string, string> Extra,
    IReadOnlyList<ShipToDeliveryRow> RecentDeliveries,
    double GeofenceRadiusM);

/// <summary>
/// The reads behind screen 1. Every method works inside ONE company, so a
/// user never sees another company's customers. Each call opens its own short
/// database context (the Blazor Server pattern, see UserAdmin).
/// </summary>
public class CustomerQueries(IDbContextFactory<TruckGoDb> dbFactory)
{
    /// <summary>How many deliveries the ship-to page lists (newest first).</summary>
    public const int RecentDeliveryCount = 20;

    /// <summary>All customers of the company, by name, with how many ship-tos each has.</summary>
    public async Task<List<CustomerRow>> ListAsync(Guid companyId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Customers
            .Where(c => c.CompanyId == companyId)
            .OrderBy(c => c.Name)
            .Select(c => new CustomerRow(c.Id, c.ExternalCode, c.Name, c.City, c.Country,
                c.ShipTos.Count, c.IsActive, c.LastReceivedAt))
            .ToListAsync();
    }

    /// <summary>One customer with its ship-tos; null if it is not this company's.</summary>
    public async Task<CustomerDetail?> GetAsync(Guid companyId, Guid customerId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var c = await db.Customers.AsNoTracking()
            .Include(x => x.ShipTos)
            .FirstOrDefaultAsync(x => x.Id == customerId && x.CompanyId == companyId);
        if (c is null) return null;

        var shipTos = c.ShipTos
            .OrderByDescending(s => s.IsActive).ThenBy(s => s.Name)
            .Select(s => new ShipToRow(s.Id, s.ExternalCode, s.Name, s.Address, s.City,
                s.Latitude, s.Longitude, s.ContactName, s.ContactPhone, s.IsActive))
            .ToList();

        return new CustomerDetail(c.Id, c.ExternalCode, c.Name, c.Address, c.City, c.Postcode,
            c.Country, c.Phone, c.TaxId, c.IsActive, c.LastReceivedAt, c.Extra, shipTos,
            await RadiusAsync(db, companyId));
    }

    /// <summary>One ship-to with its customer and recent deliveries; null if not this company's.</summary>
    public async Task<ShipToDetail?> GetShipToAsync(Guid companyId, Guid shipToId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var s = await db.ShipTos.AsNoTracking()
            .Include(x => x.Customer)
            .FirstOrDefaultAsync(x => x.Id == shipToId && x.CompanyId == companyId);
        if (s is null) return null;

        var deliveries = await db.Deliveries
            .Where(d => d.ShipToId == s.Id)
            .OrderByDescending(d => d.ScheduledAt)
            .Take(RecentDeliveryCount)
            .Select(d => new ShipToDeliveryRow(d.Plant.ExternalCode, d.Number, d.ScheduledAt,
                d.Material, d.OrderedTons, d.TruckPlate, d.Status))
            .ToListAsync();

        return new ShipToDetail(s.Id, s.ExternalCode, s.Name, s.CustomerId, s.Customer.ExternalCode,
            s.Customer.Name, s.Address, s.City, s.Postcode, s.Country, s.Latitude, s.Longitude,
            s.ContactName, s.ContactPhone, s.DeliveryInstructions, s.OpeningHours, s.IsActive,
            s.LastReceivedAt, s.Extra, deliveries, await RadiusAsync(db, companyId));
    }

    // The one geofence radius of the company (TruckGo setting, not master data)
    private static async Task<double> RadiusAsync(TruckGoDb db, Guid companyId) =>
        (await db.Settings.AsNoTracking().FirstOrDefaultAsync(x => x.CompanyId == companyId)
            ?? new CompanySettings()).GeofenceRadiusM;
}
