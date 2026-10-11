using Microsoft.EntityFrameworkCore;
using TruckGo.Data;
using TruckGo.Queries;

namespace TruckGo.Api.Tests;

/// <summary>The reads behind the Vehicles screen (TruckGo.Core/Queries).</summary>
public class VehicleQueriesTests
{
    [Fact]
    public async Task The_list_has_trucks_then_trailers_with_their_agent_and_all_idle()
    {
        using var db = await TestDb.SeededAsync();
        var vehicles = await new VehicleQueries(db).ListAsync(await db.DemoCompanyAsync());

        Assert.Equal(14, vehicles.Count);
        Assert.Equal(8, vehicles.TakeWhile(v => v.Kind == VehicleKind.Truck).Count()); // trucks first
        Assert.Equal("Midlands Haulage Ltd", vehicles.Single(v => v.Plate == SeedData.DemoTruck).ForwardingAgentName);
        Assert.Null(vehicles.Single(v => v.Plate == "PL-4417").ForwardingAgentName); // the agent is optional
        Assert.All(vehicles, v => Assert.Equal(VehicleState.Idle, v.State));        // nothing has started yet
    }

    [Theory]
    [InlineData(DeliveryStatus.Loading, VehicleState.AtPlant)]
    [InlineData(DeliveryStatus.InTransit, VehicleState.OnTheRoad)]
    [InlineData(DeliveryStatus.Unloading, VehicleState.AtShipTo)]
    public async Task Truck_and_trailer_follow_the_status_of_their_delivery(DeliveryStatus status, VehicleState expected)
    {
        using var db = await TestDb.SeededAsync();
        var queries = new VehicleQueries(db);
        var company = await db.DemoCompanyAsync();
        await using (var ctx = db.CreateDbContext())
        {
            (await ctx.Deliveries.SingleAsync(d => d.Number == "422211")).Status = status;
            await ctx.SaveChangesAsync();
        }

        var vehicles = await queries.ListAsync(company);
        var truck = vehicles.Single(v => v.Plate == SeedData.DemoTruck);
        Assert.Equal(expected, truck.State);
        Assert.Equal("422211", truck.Current!.Number);
        Assert.Equal("Riverside Arena Works", truck.Current.ShipToName);
        Assert.Equal(expected, vehicles.Single(v => v.Plate == SeedData.DemoTrailer).State); // the trailer too
        Assert.Equal(VehicleState.Idle, vehicles.Single(v => v.Plate == "TG-5821").State);
    }

    [Fact]
    public async Task A_vehicle_page_lists_its_deliveries_newest_first()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new VehicleQueries(db);
        var company = await db.DemoCompanyAsync();
        var trailerId = (await queries.ListAsync(company)).Single(v => v.Plate == SeedData.DemoTrailer).Id;

        var trailer = (await queries.GetAsync(company, trailerId))!;
        Assert.Equal(VehicleKind.Trailer, trailer.Kind);
        Assert.Equal("FA-01", trailer.ForwardingAgentCode);
        Assert.Equal(5, trailer.RecentDeliveries.Count); // all demo deliveries use this trailer
        Assert.True(trailer.RecentDeliveries.Zip(trailer.RecentDeliveries.Skip(1)).All(p => p.First.ScheduledAt >= p.Second.ScheduledAt));
        Assert.Null(trailer.Current);

        Assert.Null(await queries.GetAsync(Guid.NewGuid(), trailerId)); // another company
    }
}
