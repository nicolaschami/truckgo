using TruckGo.Data;
using TruckGo.Queries;

namespace TruckGo.Api.Tests;

/// <summary>The reads behind the Deliveries screen (TruckGo.Core/Queries).</summary>
public class DeliveryQueriesTests
{
    private static readonly DateTime Now = DateTime.UtcNow;

    [Fact]
    public async Task A_day_lists_its_deliveries_by_planned_time_and_the_plant_filter_works()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new DeliveryQueries(db);
        var company = await db.DemoCompanyAsync();
        var today = Now.Date;

        // Demo data: 3 deliveries planned today (08:00, 08:53, 09:46 UTC)
        var day = await queries.ListAsync(company, today, today.AddDays(1), null, Now);
        Assert.Equal(["422211", "422215", "422214"], day.Select(d => d.Number));
        Assert.All(day, d => Assert.Equal(DeliveryStatus.Assigned, d.Status));

        // Yesterday: the two delivered ones, with their net weight
        var yesterday = await queries.ListAsync(company, today.AddDays(-1), today, null, Now);
        Assert.Equal(20.04, yesterday.Single(d => d.Number == "421987").NetTons);

        // Only plant QS1
        var plantId = (await new PlantQueries(db).ListAsync(company, today, today.AddDays(1))).Single(p => p.Code == "QS1").Id;
        Assert.Equal(["422214"], (await queries.ListAsync(company, today, today.AddDays(1), plantId, Now)).Select(d => d.Number));
    }

    [Fact]
    public async Task A_delivery_page_has_its_site_weights_and_vehicle_links()
    {
        using var db = await TestDb.SeededAsync();
        var queries = new DeliveryQueries(db);
        var company = await db.DemoCompanyAsync();
        var id = (await queries.ListAsync(company, Now.Date.AddDays(-1), Now.Date, null, Now)).Single(d => d.Number == "421987").Id;

        var d = (await queries.GetAsync(company, id, Now))!;
        Assert.Equal("QN2", d.PlantCode);
        Assert.Equal("Riverside Arena Works", d.ShipToName);
        Assert.Contains("north gate", d.DeliveryInstructions);
        Assert.Equal(2, d.Weighings.Count);
        Assert.Equal(WeighingKind.First, d.Weighings[0].Kind); // oldest first
        Assert.Equal((14.20, 34.24, 20.04), (d.TareTons!.Value, d.GrossTons!.Value, d.NetTons!.Value));
        Assert.NotNull(d.TruckId);   // AB-1234 links to its vehicle page
        Assert.NotNull(d.TrailerId); // TR-1001 too

        Assert.Null(await queries.GetAsync(Guid.NewGuid(), id, Now)); // another company
    }

    [Fact]
    public async Task Deliveries_under_way_carry_the_live_board_warnings()
    {
        using var db = await TestDb.SeededAsync();
        await using (var ctx = db.CreateDbContext()) await DemoDay.PlayAsync(ctx, Now);
        var rows = await new DeliveryQueries(db).ListAsync(await db.DemoCompanyAsync(), Now.AddHours(-6), Now.AddHours(6), null, Now);

        Assert.Equal(Attention.Danger, rows.Single(d => d.Number == "900104").Attention); // late on the road
        Assert.Equal(Attention.None, rows.Single(d => d.Number == "900108").Attention);   // delivered: no warning
    }
}
