using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using TruckGo.Api.Auth;
using TruckGo.Data;

namespace TruckGo.Api.Tracking;

/// <summary>
/// One GPS point from the app. <paramref name="ClientId"/> is made by the
/// phone (a new UUID per point) so a batch sent twice is stored once.
/// The delivery, when the truck is working on one, is given like everywhere
/// in the app: plant code + delivery number.
/// </summary>
public record PositionIn(
    Guid ClientId,
    string TruckPlate,
    double Latitude,
    double Longitude,
    DateTime RecordedAt,
    double? AccuracyM = null,
    double? SpeedKmh = null,
    double? Heading = null,
    string? PlantCode = null,
    string? DeliveryNumber = null);

/// <summary>What the server did with a batch: new points stored, repeats ignored.</summary>
public record PositionsResult(int Stored, int AlreadyReceived);

public static class PositionEndpoints
{
    /// <summary>Most points one call may carry (about 8 hours at one point a minute).</summary>
    public const int MaxBatch = 500;

    public static void MapPositionEndpoints(this IEndpointRouteBuilder api)
    {
        api.MapPost("/positions", PostPositions)
            .RequireAuthorization()
            .WithTags("Tracking")
            .WithSummary("Send a batch of GPS points (offline-safe: points already received are ignored)");
    }

    private static async Task<IResult> PostPositions(
        List<PositionIn> points, ClaimsPrincipal user, TruckGoDb db, TimeProvider clock)
    {
        if (points.Count == 0) return Results.Ok(new PositionsResult(0, 0));
        if (points.Count > MaxBatch)
            return Results.Problem(statusCode: 400, title: "Too many points", detail: $"Send at most {MaxBatch} points per call.");
        if (points.Any(p => p.Latitude is < -90 or > 90 || p.Longitude is < -180 or > 180))
            return Results.Problem(statusCode: 400, title: "Bad position", detail: "Latitude must be -90..90 and longitude -180..180.");

        var company = user.CompanyId();
        var driver = user.DriverId();
        var now = clock.GetUtcNow().UtcDateTime;

        // Points this server already has (the same batch sent again): skip them
        var ids = points.Select(p => p.ClientId).Distinct().ToList();
        var known = (await db.Positions.Where(p => ids.Contains(p.ClientId)).Select(p => p.ClientId).ToListAsync()).ToHashSet();

        // The deliveries named in the batch (plant + number), inside the driver's company
        var keys = points.Where(p => p.PlantCode is not null && p.DeliveryNumber is not null)
            .Select(p => (p.PlantCode!, p.DeliveryNumber!)).Distinct().ToList();
        var numbers = keys.Select(k => k.Item2).ToList();
        var deliveries = (await db.Deliveries
                .Where(d => d.CompanyId == company && numbers.Contains(d.Number))
                .Select(d => new { d.Id, PlantCode = d.Plant.ExternalCode, d.Number })
                .ToListAsync())
            .ToDictionary(d => (d.PlantCode, d.Number), d => d.Id);

        var stored = 0;
        foreach (var p in points.DistinctBy(p => p.ClientId).Where(p => !known.Contains(p.ClientId)))
        {
            db.Positions.Add(new GpsPosition
            {
                Id = Guid.NewGuid(),
                CompanyId = company,
                ClientId = p.ClientId,
                TruckPlate = p.TruckPlate.Trim().ToUpperInvariant(),
                DeliveryId = p.PlantCode is not null && p.DeliveryNumber is not null
                    && deliveries.TryGetValue((p.PlantCode, p.DeliveryNumber), out var id) ? id : null,
                DriverId = driver,
                Latitude = p.Latitude,
                Longitude = p.Longitude,
                AccuracyM = p.AccuracyM,
                SpeedKmh = p.SpeedKmh,
                Heading = p.Heading,
                RecordedAt = p.RecordedAt.ToUniversalTime(),
                ReceivedAt = now,
            });
            stored++;
        }
        await db.SaveChangesAsync();

        return Results.Ok(new PositionsResult(stored, points.Count - stored));
    }
}
