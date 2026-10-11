using Microsoft.EntityFrameworkCore;
using TruckGo.Data;
using TruckGo.Queries;

namespace TruckGo.Api.Tests;

/// <summary>The reads behind screen 2, Plants (TruckGo.Core/Queries).</summary>
public class PlantQueriesTests
{
    // "Today" as the screen would pass it: the whole current UTC day
    private static readonly DateTime From = DateTime.UtcNow.Date;
    private static readonly DateTime To = From.AddDays(1);

    [Fact]
    public async Task The_list_counts_todays_deliveries_and_trucks_at_each_plant()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new PlantQueries(db);
        var company = await db.DemoCompanyAsync();

        var plants = await queries.ListAsync(company, From, To);
        Assert.Equal(["Quarry North - Plant 2", "Quarry South - Plant 1"], plants.Select(p => p.Name));

        // Demo data: QN2 has 2 deliveries today (and 2 from yesterday), QS1 has 1
        var north = plants.Single(p => p.Code == "QN2");
        Assert.Equal(2, north.DeliveriesToday);
        Assert.Equal(1, plants.Single(p => p.Code == "QS1").DeliveriesToday);
        Assert.Equal(0, north.TrucksAtPlant); // nobody has arrived yet
    }

    [Fact]
    public async Task A_truck_that_arrived_shows_at_the_plant_with_its_delivery()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new PlantQueries(db);
        var company = await db.DemoCompanyAsync();

        // The demo truck enters the QN2 geofence for 422211
        await using (var ctx = db.CreateDbContext())
        {
            var d = await ctx.Deliveries.SingleAsync(x => x.Number == "422211");
            d.Status = DeliveryStatus.AtPlant;
            d.UpdatedAt = DateTime.UtcNow.AddMinutes(-12);
            await ctx.SaveChangesAsync();
        }

        var northId = (await queries.ListAsync(company, From, To)).Single(p => p.Code == "QN2").Id;
        Assert.Equal(1, (await queries.ListAsync(company, From, To)).Single(p => p.Code == "QN2").TrucksAtPlant);

        var plant = (await queries.GetAsync(company, northId, From, To))!;
        var here = Assert.Single(plant.AtPlantNow);
        Assert.Equal(SeedData.DemoTruck, here.TruckPlate);
        Assert.Equal("Northgate Construction Ltd", here.CustomerName);
        Assert.InRange((DateTime.UtcNow - here.Since).TotalMinutes, 11, 13);

        Assert.Equal(["422211", "422215"], plant.Today.Select(d => d.Number)); // by planned time
        Assert.Equal(200, plant.GeofenceRadiusM);
    }

    [Fact]
    public async Task Another_companys_plants_are_not_found()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new PlantQueries(db);
        var plant = (await queries.ListAsync(await db.DemoCompanyAsync(), From, To)).First();
        var otherCompany = Guid.NewGuid();

        Assert.Empty(await queries.ListAsync(otherCompany, From, To));
        Assert.Null(await queries.GetAsync(otherCompany, plant.Id, From, To));
    }
}
