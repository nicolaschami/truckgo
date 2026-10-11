using TruckGo.Data;
using TruckGo.Queries;

namespace TruckGo.Api.Tests;

/// <summary>The live board (screen 7): the cards, the warning rules, the demo day.</summary>
public class LiveBoardTests
{
    private static readonly DateTime Now = DateTime.UtcNow;
    private static readonly DateTime From = Now.Date;
    private static readonly DateTime To = From.AddDays(1);

    [Fact]
    public async Task Without_work_under_way_every_truck_is_idle()
    {
        using var db = await TestDb.SeededAsync();
        var board = await new LiveBoardQueries(db).GetAsync(await db.DemoCompanyAsync(), null, From, To, Now);

        Assert.Empty(board.Cards);
        Assert.Equal(8, board.Totals.Idle);
        Assert.Equal(2, board.Plants.Count);
        // The demo truck has today's deliveries planned: shown with its next one
        Assert.Equal("422211", board.Idle.Single(t => t.Plate == SeedData.DemoTruck).NextNumber);
    }

    [Fact]
    public async Task The_demo_day_fills_every_column_with_the_right_warnings()
    {
        // "Today" here = 6 hours around now: holds the demo day (planned up to 3 h ago)
        // whatever the time of the run, and leaves out yesterday's seeded deliveries
        var (from, to) = (Now.AddHours(-6), Now.AddHours(6));
        using var db = await TestDb.SeededAsync();
        await using (var ctx = db.CreateDbContext()) await DemoDay.PlayAsync(ctx, Now);

        var board = await new LiveBoardQueries(db).GetAsync(await db.DemoCompanyAsync(), null, from, to, Now);
        Assert.Equal(3, board.Totals.AtPlant);    // 900101 loading, 900102 waiting, 900107 waiting long
        Assert.Equal(2, board.Totals.OnTheRoad);  // 900103, 900104 (late)
        Assert.Equal(2, board.Totals.AtShipTo);   // 900105, 900106
        Assert.Equal(2, board.Totals.DeliveredToday);
        Assert.Equal(41.4, board.Totals.DeliveredTonsToday); // net weights: 19.7 + 21.7

        Attention Of(string number) => board.Cards.Single(c => c.Number == number).Attention;
        Assert.Equal(Attention.None, Of("900101"));    // loading 12 min (limit 30)
        Assert.Equal(Attention.Warning, Of("900102")); // 41 min at the plant
        Assert.Equal(Attention.Danger, Of("900107"));  // 95 min = over twice the limit
        Assert.Equal(Attention.None, Of("900103"));    // on time
        Assert.Equal(Attention.Danger, Of("900104"));  // late for its window
        Assert.Equal(Attention.Warning, Of("900106")); // unloading 52 min (limit 45)
        Assert.Equal(4, board.Totals.Warnings);

        // Running it again resets the times instead of adding deliveries
        await using (var ctx = db.CreateDbContext()) await DemoDay.PlayAsync(ctx, Now);
        Assert.Equal(7, (await new LiveBoardQueries(db).GetAsync(await db.DemoCompanyAsync(), null, From, To, Now)).Cards.Count);
    }

    [Fact]
    public async Task The_plant_filter_keeps_only_that_plants_work()
    {
        using var db = await TestDb.SeededAsync();
        await using (var ctx = db.CreateDbContext()) await DemoDay.PlayAsync(ctx, Now);
        var queries = new LiveBoardQueries(db);
        var company = await db.DemoCompanyAsync();
        var qs1 = (await queries.GetAsync(company, null, From, To, Now)).Plants.Single(p => p.Code == "QS1");

        var board = await queries.GetAsync(company, qs1.Id, From, To, Now);
        Assert.All(board.Cards, c => Assert.Equal("QS1", c.PlantCode));
        Assert.Equal(3, board.Cards.Count); // 900103, 900105, 900107
    }

    [Theory]
    [InlineData(29, Attention.None)]
    [InlineData(30, Attention.Warning)]
    [InlineData(60, Attention.Danger)]
    public void Waiting_rules_follow_the_settings_limit(double minutes, Attention expected)
    {
        var (attention, _) = LiveBoardQueries.Judge(VehicleState.AtPlant, minutes, 30, Now.AddHours(1), Now, 0);
        Assert.Equal(expected, attention);
    }

    [Fact]
    public void On_the_road_is_late_only_after_the_window_and_its_tolerance()
    {
        var windowEnd = Now.AddMinutes(-10);
        Assert.Equal(Attention.Danger, LiveBoardQueries.Judge(VehicleState.OnTheRoad, 50, null, windowEnd, Now, 0).Item1);
        Assert.Equal(Attention.None, LiveBoardQueries.Judge(VehicleState.OnTheRoad, 50, null, windowEnd, Now, 15).Item1);
    }
}
