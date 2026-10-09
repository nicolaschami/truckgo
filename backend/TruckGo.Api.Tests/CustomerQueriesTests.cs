using Microsoft.EntityFrameworkCore;
using TruckGo.Data;
using TruckGo.Queries;

namespace TruckGo.Api.Tests;

/// <summary>The reads behind screen 1, Customers → ship-tos (TruckGo.Core/Queries).</summary>
public class CustomerQueriesTests
{
    [Fact]
    public async Task The_list_shows_every_customer_with_its_ship_to_count()
    {
        using var db = await TestDb.SeededAsync();
        var customers = await new CustomerQueries(db).ListAsync(await db.DemoCompanyAsync());

        Assert.Equal(4, customers.Count);
        var northgate = customers.Single(c => c.Code == "100245");
        Assert.Equal("Northgate Construction Ltd", northgate.Name);
        Assert.Equal(2, northgate.ShipToCount);
        Assert.False(customers.Single(c => c.Code == "100999").IsActive); // the closed one is kept, marked inactive
    }

    [Fact]
    public async Task A_customer_page_has_its_details_ship_tos_and_the_radius_setting()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new CustomerQueries(db);
        var company = await db.DemoCompanyAsync();
        var id = (await queries.ListAsync(company)).Single(c => c.Code == "100245").Id;

        var customer = (await queries.GetAsync(company, id))!;
        Assert.Equal("GB100245000", customer.TaxId);
        Assert.Equal(["Canal Basin Apartments", "Riverside Arena Works"], customer.ShipTos.Select(s => s.Name));
        Assert.Equal(200, customer.GeofenceRadiusM);
    }

    [Fact]
    public async Task A_ship_to_page_has_its_instructions_extra_info_and_newest_deliveries_first()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new CustomerQueries(db);
        var company = await db.DemoCompanyAsync();
        Guid shipToId;
        await using (var ctx = db.CreateDbContext())
            shipToId = (await ctx.ShipTos.SingleAsync(s => s.ExternalCode == "100245-01")).Id;

        var shipTo = (await queries.GetShipToAsync(company, shipToId))!;
        Assert.Equal("Northgate Construction Ltd", shipTo.CustomerName);
        Assert.Equal("4512", shipTo.Extra["Gate code"]);
        Assert.Contains("north gate", shipTo.DeliveryInstructions);

        // Today's 422211 before yesterday's 421987
        Assert.Equal(["422211", "421987"], shipTo.RecentDeliveries.Select(d => d.Number));
        Assert.Equal(DeliveryStatus.Delivered, shipTo.RecentDeliveries[1].Status);
    }

    [Fact]
    public async Task Another_companys_customers_and_ship_tos_are_not_found()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new CustomerQueries(db);
        var company = await db.DemoCompanyAsync();
        var customer = (await queries.ListAsync(company)).First();
        var otherCompany = Guid.NewGuid();

        Assert.Empty(await queries.ListAsync(otherCompany));
        Assert.Null(await queries.GetAsync(otherCompany, customer.Id));
    }
}
