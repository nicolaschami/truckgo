using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using TruckGo.Api.Auth;
using TruckGo.Data;

namespace TruckGo.Api.Deliveries;

/// <summary>
/// What the app shows in its truck list. Not stored: calculated from the
/// deliveries — "in use" when the vehicle is on a delivery that has started
/// (at plant ... unloading), otherwise "available".
/// </summary>
public enum VehicleStatus { Available, InUse }

/// <summary>A truck or trailer for the app's truck selection.</summary>
public record VehicleDto(string Plate, bool IsTruck, string Model, string Detail, VehicleStatus Status);

/// <summary>
/// A delivery as the app needs it: plant and site with their geofence, and
/// the weighbridge readings. 1st weight = tare, 2nd = gross; null = not yet.
/// The shape stays the app's even though the database now keeps customer and
/// ship-to as separate records: the fields are filled from them.
/// Both geofence radii come from the company's one radius setting.
/// </summary>
public record DeliveryDto(
    string Number,
    string PlantCode,
    string PlantName,
    double PlantLatitude,
    double PlantLongitude,
    double PlantGeofenceRadiusM,
    string OrderNumber,
    string? TruckPlate,
    string? TrailerPlate,
    string SoldToCode,
    string SoldToName,
    string ShipToCode,
    string ShipToName,
    string ShipToAddress,
    double SiteLatitude,
    double SiteLongitude,
    double SiteGeofenceRadiusM,
    string SiteContact,
    string? SitePhone,
    string Material,
    double OrderedTons,
    double? TareTons,
    DateTime? TareWeighedAt,
    double? GrossTons,
    DateTime? GrossWeighedAt,
    double? LoadedTons,
    string? WeighbridgeTicket,
    DateTime ScheduledAt,
    DateTime WindowStart,
    DateTime WindowEnd,
    double DistanceKm,
    string? Notes,
    DeliveryStatus Status,
    DateTime UpdatedAt);

/// <summary>"since" lets the app ask only for what changed since its last call.</summary>
public record DeliveriesResponse(DateTime ServerTime, IReadOnlyList<DeliveryDto> Deliveries);

public static class DeliveryEndpoints
{
    public static void MapDeliveryEndpoints(this IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("").RequireAuthorization().WithTags("Deliveries");

        group.MapGet("/vehicles", GetVehicles)
            .WithSummary("Active trucks and trailers of the driver's company");

        group.MapGet("/trucks/{plate}/deliveries", GetTruckDeliveries)
            .WithSummary("Deliveries assigned to a truck; with ?since= only those changed since then");

        group.MapGet("/deliveries/{plantCode}/{number}", GetDelivery)
            .WithSummary("One delivery, with its 1st and 2nd weight (polled at the weighbridge)");
    }

    /// <summary>Statuses of a delivery that has started but is not finished.</summary>
    private static readonly DeliveryStatus[] Underway =
    [
        DeliveryStatus.AtPlant, DeliveryStatus.Loading, DeliveryStatus.InTransit,
        DeliveryStatus.ArrivedAtSite, DeliveryStatus.Unloading,
    ];

    private static async Task<IReadOnlyList<VehicleDto>> GetVehicles(ClaimsPrincipal user, TruckGoDb db)
    {
        var company = user.CompanyId();

        // Plates of the trucks and trailers on a delivery that has started
        var busy = await db.Deliveries
            .Where(d => d.CompanyId == company && Underway.Contains(d.Status))
            .Select(d => new { d.TruckPlate, d.TrailerPlate })
            .ToListAsync();
        var busyPlates = busy.SelectMany(b => new[] { b.TruckPlate, b.TrailerPlate })
            .OfType<string>().ToHashSet();

        // Only active vehicles: an inactive one cannot be picked in the app
        var vehicles = await db.Vehicles
            .Where(v => v.CompanyId == company && v.IsActive)
            .OrderBy(v => v.Plate)
            .AsNoTracking()
            .ToListAsync();

        return vehicles.Select(v => new VehicleDto(
            v.Plate, v.Kind == VehicleKind.Truck, v.Model, v.Description ?? "",
            busyPlates.Contains(v.Plate) ? VehicleStatus.InUse : VehicleStatus.Available)).ToList();
    }

    private static async Task<IResult> GetTruckDeliveries(
        string plate, DateTime? since, ClaimsPrincipal user, TruckGoDb db, TimeProvider clock)
    {
        var company = user.CompanyId();
        // Read the clock before the query: a change saved meanwhile is
        // returned again next time rather than missed
        var serverTime = clock.GetUtcNow().UtcDateTime;

        if (!await db.Vehicles.AnyAsync(v => v.CompanyId == company && v.Plate == plate && v.Kind == VehicleKind.Truck))
            return Results.Problem(statusCode: 404, title: "Unknown truck", detail: $"No truck '{plate}'.");

        var query = db.Deliveries
            .Where(d => d.CompanyId == company && d.TruckPlate == plate);
        if (since is { } s)
        {
            var sinceUtc = s.ToUniversalTime();
            query = query.Where(d => d.UpdatedAt > sinceUtc);
        }

        var rows = await WithDetails(query)
            .OrderBy(d => d.ScheduledAt)
            .ToListAsync();

        var radius = await GeofenceRadiusAsync(db, company);
        return Results.Ok(new DeliveriesResponse(serverTime, rows.Select(d => ToDto(d, radius)).ToList()));
    }

    private static async Task<IResult> GetDelivery(
        string plantCode, string number, ClaimsPrincipal user, TruckGoDb db)
    {
        var company = user.CompanyId();
        var row = await WithDetails(db.Deliveries)
            .FirstOrDefaultAsync(d => d.CompanyId == company
                && d.Plant.ExternalCode == plantCode && d.Number == number);

        return row is null
            ? Results.Problem(statusCode: 404, title: "Unknown delivery",
                detail: $"No delivery {plantCode}/{number}.")
            : Results.Ok(ToDto(row, await GeofenceRadiusAsync(db, company)));
    }

    /// <summary>Loads what a DeliveryDto needs: plant, customer, ship-to, weighings.</summary>
    private static IQueryable<Delivery> WithDetails(IQueryable<Delivery> query) => query
        .Include(d => d.Plant)
        .Include(d => d.Customer)
        .Include(d => d.ShipTo)
        .Include(d => d.Weighings)
        .AsNoTracking();

    /// <summary>The company's one geofence radius (default 200 m if it has no settings row yet).</summary>
    private static async Task<double> GeofenceRadiusAsync(TruckGoDb db, Guid company) =>
        (await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.CompanyId == company)
            ?? new CompanySettings()).GeofenceRadiusM;

    public static DeliveryDto ToDto(Delivery d, double geofenceRadiusM)
    {
        // The latest reading of each kind counts (a re-weigh replaces it)
        Weighing? Latest(WeighingKind kind) => d.Weighings
            .Where(w => w.Kind == kind).MaxBy(w => w.WeighedAt);
        var tare = Latest(WeighingKind.First);
        var gross = Latest(WeighingKind.Second);

        // The app shows one address line and one contact line, as before:
        // "Arena Way, Coventry" and "Dan Whitfield  •  +44 7700 900123".
        // The phone without spaces is what the app dials.
        var site = d.ShipTo;
        var address = string.Join(", ", new[] { site.Address, site.City }.Where(x => !string.IsNullOrWhiteSpace(x)));
        var contact = string.Join("  •  ", new[] { site.ContactName, site.ContactPhone }.Where(x => !string.IsNullOrWhiteSpace(x)));

        return new DeliveryDto(
            d.Number, d.Plant.ExternalCode, d.Plant.Name, d.Plant.Latitude, d.Plant.Longitude,
            geofenceRadiusM, d.OrderNumber, d.TruckPlate, d.TrailerPlate,
            d.Customer.ExternalCode, d.Customer.Name,
            site.ExternalCode, site.Name, address, site.Latitude, site.Longitude, geofenceRadiusM,
            contact, site.ContactPhone?.Replace(" ", ""), d.Material, d.OrderedTons,
            tare?.Tons, tare?.WeighedAt, gross?.Tons, gross?.WeighedAt,
            tare is not null && gross is not null ? Math.Round(gross.Tons - tare.Tons, 3) : null,
            gross?.TicketNumber ?? tare?.TicketNumber,
            d.ScheduledAt, d.WindowStart, d.WindowEnd, d.DistanceKm, d.Notes, d.Status, d.UpdatedAt);
    }
}
