using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using TruckGo.Api.Tracking;
using TruckGo.Data;
using TruckGo.Queries;

namespace TruckGo.Api.Tests;

/// <summary>Map & trace (screen 8): GPS points from the app, the live map, the traces and their stops.</summary>
public class MapTests
{
    private static readonly DateTime Now = DateTime.UtcNow;

    [Fact]
    public async Task The_app_sends_points_and_a_repeated_batch_is_stored_once()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        var batch = new List<PositionIn>
        {
            new(Guid.NewGuid(), "ab-1234", 52.5545, -1.5260, Now.AddMinutes(-2), 8, 0, null, "QN2", "422211"),
            new(Guid.NewGuid(), "AB-1234", 52.5550, -1.5250, Now.AddMinutes(-1), 8, 32, 90, "QN2", "422211"),
        };
        var first = await (await client.PostAsJsonAsync("/api/v1/positions", batch)).Content.ReadFromJsonAsync<PositionsResult>();
        Assert.Equal(new PositionsResult(2, 0), first);

        // The answer got lost: the phone sends the same batch again
        var again = await (await client.PostAsJsonAsync("/api/v1/positions", batch)).Content.ReadFromJsonAsync<PositionsResult>();
        Assert.Equal(new PositionsResult(0, 2), again);

        await api.WithDbAsync(async db =>
        {
            var points = await db.Positions.ToListAsync();
            Assert.Equal(2, points.Count);
            Assert.All(points, p => Assert.Equal("AB-1234", p.TruckPlate));     // plates normalised
            Assert.All(points, p => Assert.NotNull(p.DeliveryId));               // linked to 422211
            Assert.All(points, p => Assert.NotNull(p.DriverId));                 // test1 sent them
        });

        // Nonsense coordinates are refused
        var bad = new List<PositionIn> { new(Guid.NewGuid(), "AB-1234", 123, 0, Now) };
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/positions", bad)).StatusCode);
    }

    [Fact]
    public async Task The_live_map_shows_each_working_truck_at_its_last_point()
    {
        using var db = await TestDb.SeededAsync();
        await using (var ctx = db.CreateDbContext()) await DemoDay.PlayAsync(ctx, Now);

        var live = await new MapQueries(db).LiveAsync(await db.DemoCompanyAsync(), Now);
        Assert.Equal(7, live.Trucks.Count); // the 7 trucks of the demo day (all have a trail)
        var late = live.Trucks.Single(t => t.Plate == "KL-1188");
        Assert.Equal(VehicleState.OnTheRoad, late.State);
        Assert.Contains("900104", late.DeliveryLabel);
        Assert.False(late.Stale);
        Assert.Contains(live.Places, p => p.Kind == "plant");
        Assert.Contains(live.Places, p => p.Kind == "site");
    }

    [Fact]
    public async Task A_delivery_trace_has_its_route_and_the_unexpected_stop()
    {
        using var db = await TestDb.SeededAsync();
        await using (var ctx = db.CreateDbContext()) await DemoDay.PlayAsync(ctx, Now);
        Guid lateId, onTimeId;
        await using (var ctx = db.CreateDbContext())
        {
            lateId = (await ctx.Deliveries.SingleAsync(d => d.Number == "900104")).Id;
            onTimeId = (await ctx.Deliveries.SingleAsync(d => d.Number == "900108")).Id;
        }
        var queries = new MapQueries(db);
        var company = await db.DemoCompanyAsync();

        var late = (await queries.DeliveryTraceAsync(company, lateId))!;
        Assert.True(late.Points.Count > 60);                // loading + an hour on the road, a point a minute
        Assert.True(late.DistanceKm > 5);
        var stop = Assert.Single(late.Stops);               // the 20-minute stop half way
        Assert.InRange(stop.Minutes, 15, 21);

        var delivered = (await queries.DeliveryTraceAsync(company, onTimeId))!;
        Assert.Empty(delivered.Stops);                      // waiting at the plant and the site is not a stop

        var truckDay = await queries.TruckTraceAsync(company, "TG-5821", Now.AddHours(-6), Now.AddMinutes(1));
        Assert.True(truckDay.Points.Count > delivered.Points.Count); // two deliveries that day

        Assert.Null(await queries.DeliveryTraceAsync(Guid.NewGuid(), lateId)); // another company
    }

    [Fact]
    public void Standing_still_long_enough_outside_the_places_is_a_stop()
    {
        var start = Now.AddHours(-1);
        var points = Enumerable.Range(0, 30)
            .Select(i => new TracePoint(52.40 + (i < 5 || i > 24 ? i * 0.002 : 0.01), -1.50, start.AddMinutes(i), null))
            .ToList();
        // Standing still from minute 5 to minute 24 = 19 minutes, limit 15
        Assert.Single(MapQueries.FindStops(points, 15, [], 200));
        // The same, but inside a plant's geofence: normal waiting, no stop
        Assert.Empty(MapQueries.FindStops(points, 15, [new MapPlace("plant", "P", 52.41, -1.50, "/")], 200));
    }
}
