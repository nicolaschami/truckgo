using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using TruckGo.Api.Auth;
using TruckGo.Api.Data;

namespace TruckGo.Api.Deliveries;

public record VehicleDto(string Plate, bool IsTruck, string Model, string Detail, VehicleStatus Status);

/// <summary>
/// A delivery as the app needs it: plant and site with their geofence, and
/// the weighbridge readings. 1st weight = tare, 2nd = gross; null = not yet.
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
    string SoldToCode,
    string SoldToName,
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
            .WithSummary("Trucks and trailers of the driver's company");

        group.MapGet("/trucks/{plate}/deliveries", GetTruckDeliveries)
            .WithSummary("Deliveries assigned to a truck; with ?since= only those changed since then");

        group.MapGet("/deliveries/{plantCode}/{number}", GetDelivery)
            .WithSummary("One delivery, with its 1st and 2nd weight (polled at the weighbridge)");
    }

    private static async Task<IReadOnlyList<VehicleDto>> GetVehicles(ClaimsPrincipal user, TruckGoDb db)
    {
        var company = user.CompanyId();
        return await db.Vehicles
            .Where(v => v.CompanyId == company)
            .OrderBy(v => v.Plate)
            .Select(v => new VehicleDto(v.Plate, v.IsTruck, v.Model, v.Detail, v.Status))
            .ToListAsync();
    }

    private static async Task<IResult> GetTruckDeliveries(
        string plate, DateTime? since, ClaimsPrincipal user, TruckGoDb db, TimeProvider clock)
    {
        var company = user.CompanyId();
        // Read the clock before the query: a change saved meanwhile is
        // returned again next time rather than missed
        var serverTime = clock.GetUtcNow().UtcDateTime;

        if (!await db.Vehicles.AnyAsync(v => v.CompanyId == company && v.Plate == plate && v.IsTruck))
            return Results.Problem(statusCode: 404, title: "Unknown truck", detail: $"No truck '{plate}'.");

        var query = db.Deliveries
            .Where(d => d.CompanyId == company && d.TruckPlate == plate);
        if (since is { } s)
        {
            var sinceUtc = s.ToUniversalTime();
            query = query.Where(d => d.UpdatedAt > sinceUtc);
        }

        var rows = await query
            .Include(d => d.Plant)
            .Include(d => d.Weighings)
            .OrderBy(d => d.ScheduledAt)
            .AsNoTracking()
            .ToListAsync();

        return Results.Ok(new DeliveriesResponse(serverTime, rows.Select(ToDto).ToList()));
    }

    private static async Task<IResult> GetDelivery(
        string plantCode, string number, ClaimsPrincipal user, TruckGoDb db)
    {
        var company = user.CompanyId();
        var row = await db.Deliveries
            .Include(d => d.Plant)
            .Include(d => d.Weighings)
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.CompanyId == company
                && d.Plant.Code == plantCode && d.Number == number);

        return row is null
            ? Results.Problem(statusCode: 404, title: "Unknown delivery",
                detail: $"No delivery {plantCode}/{number}.")
            : Results.Ok(ToDto(row));
    }

    public static DeliveryDto ToDto(Delivery d)
    {
        // The latest reading of each kind counts (a re-weigh replaces it)
        Weighing? Latest(WeighingKind kind) => d.Weighings
            .Where(w => w.Kind == kind).MaxBy(w => w.WeighedAt);
        var tare = Latest(WeighingKind.First);
        var gross = Latest(WeighingKind.Second);

        return new DeliveryDto(
            d.Number, d.Plant.Code, d.Plant.Name, d.Plant.Latitude, d.Plant.Longitude,
            d.Plant.GeofenceRadiusM, d.OrderNumber, d.TruckPlate, d.SoldToCode, d.SoldToName,
            d.ShipToName, d.ShipToAddress, d.SiteLatitude, d.SiteLongitude, d.SiteGeofenceRadiusM,
            d.SiteContact, d.SitePhone, d.Material, d.OrderedTons,
            tare?.Tons, tare?.WeighedAt, gross?.Tons, gross?.WeighedAt,
            tare is not null && gross is not null ? Math.Round(gross.Tons - tare.Tons, 3) : null,
            gross?.TicketNumber ?? tare?.TicketNumber,
            d.ScheduledAt, d.WindowStart, d.WindowEnd, d.DistanceKm, d.Notes, d.Status, d.UpdatedAt);
    }
}
