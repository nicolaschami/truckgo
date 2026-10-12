using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using TruckGo.Data;
using TruckGo.Api.Deliveries;
using TruckGo.Integration;

namespace TruckGo.Api.Tests;

public class DeliveryTests
{
    // The JSON format the app reads: camelCase, enums as "inTransit"
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    [Fact]
    public async Task Vehicles_lists_trucks_and_trailers()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        var vehicles = await client.GetFromJsonAsync<List<VehicleDto>>("/api/v1/vehicles", Json);
        Assert.Equal(14, vehicles!.Count);
        Assert.Contains(vehicles, v => v.Plate == "AB-1234" && v.IsTruck);
        Assert.Contains(vehicles, v => v.Plate == "TR-1001" && !v.IsTruck);
    }

    [Fact]
    public async Task Truck_deliveries_include_plant_site_and_weights()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        var result = await client.GetFromJsonAsync<DeliveriesResponse>(
            "/api/v1/trucks/AB-1234/deliveries", Json);
        Assert.Equal(5, result!.Deliveries.Count);

        // A delivered one, with its 1st and 2nd weight
        var done = result.Deliveries.Single(d => d.Number == "421987");
        Assert.Equal(DeliveryStatus.Delivered, done.Status);
        Assert.Equal(14.20, done.TareTons);
        Assert.Equal(34.24, done.GrossTons);
        Assert.Equal(20.04, done.LoadedTons);
        Assert.Equal("QN2", done.PlantCode);
        Assert.Equal(200, done.PlantGeofenceRadiusM);

        // An open one: no weights yet
        var next = result.Deliveries.Single(d => d.Number == "422211");
        Assert.Equal(DeliveryStatus.Assigned, next.Status);
        Assert.Null(next.TareTons);
        Assert.Null(next.LoadedTons);
        Assert.Equal("+447700900123", next.SitePhone);

        // Filled from the ship-to record and the assigned trailer
        Assert.Equal("100245-01", next.ShipToCode);
        Assert.Equal("Arena Way, Coventry", next.ShipToAddress);
        Assert.Equal("Dan Whitfield  •  +44 7700 900123", next.SiteContact);
        Assert.Equal(SeedData.DemoTrailer, next.TrailerPlate);
    }

    [Fact]
    public async Task Json_uses_the_app_names_and_utc_times()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        using var doc = JsonDocument.Parse(await client.GetStringAsync("/api/v1/deliveries/QN2/422211"));
        var root = doc.RootElement;
        Assert.Equal("assigned", root.GetProperty("status").GetString());
        Assert.Equal(JsonValueKind.Null, root.GetProperty("tareTons").ValueKind);
        Assert.EndsWith("Z", root.GetProperty("scheduledAt").GetString());
    }

    [Fact]
    public async Task Since_returns_only_what_changed()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        var first = await client.GetFromJsonAsync<DeliveriesResponse>(
            "/api/v1/trucks/AB-1234/deliveries", Json);
        var since = Uri.EscapeDataString(first!.ServerTime.ToString("O"));

        // Nothing changed yet
        var none = await client.GetFromJsonAsync<DeliveriesResponse>(
            $"/api/v1/trucks/AB-1234/deliveries?since={since}", Json);
        Assert.Empty(none!.Deliveries);

        // The weighbridge sends the 1st weight of 422211
        await api.WithDbAsync(async db =>
        {
            var d = await db.Deliveries.Include(x => x.Weighings).SingleAsync(x => x.Number == "422211");
            d.Weighings.Add(new Weighing { Id = Guid.NewGuid(), Kind = WeighingKind.First, Tons = 14.1, WeighedAt = DateTime.UtcNow });
            d.Status = DeliveryStatus.Loading;
            d.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
        });

        var changed = await client.GetFromJsonAsync<DeliveriesResponse>(
            $"/api/v1/trucks/AB-1234/deliveries?since={since}", Json);
        var d = Assert.Single(changed!.Deliveries);
        Assert.Equal("422211", d.Number);
        Assert.Equal(14.1, d.TareTons);
        Assert.Equal(DeliveryStatus.Loading, d.Status);
    }

    [Fact]
    public async Task The_full_list_leaves_out_deliveries_finished_long_ago()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        // 421987 was delivered a month ago: the phone no longer keeps it
        await api.WithDbAsync(async db =>
        {
            var d = await db.Deliveries.SingleAsync(x => x.Number == "421987");
            d.UpdatedAt = DateTime.UtcNow.AddDays(-30);
            await db.SaveChangesAsync();
        });

        var all = await client.GetFromJsonAsync<DeliveriesResponse>("/api/v1/trucks/AB-1234/deliveries", Json);
        Assert.DoesNotContain(all!.Deliveries, d => d.Number == "421987");
        Assert.Contains(all.Deliveries, d => d.Number == "422211"); // open: always there
    }

    // --- A delivery moved to another truck ------------------------------------

    /// <summary>The other system re-sends delivery 422211 with another truck (or none).</summary>
    private static Task MoveAsync(TestApi api, string? truck) =>
        api.ImportAsync((import, company) => import.SaveDeliveryAsync(company, new DeliveryMessage(
            "QN2", "422211", "30771239", "100245", "100245-01", "AC 32 dense base 40/60", 20,
            DateTime.UtcNow, DateTime.UtcNow, DateTime.UtcNow.AddMinutes(30), TruckPlate: truck)));

    /// <summary>Asks for a truck's deliveries, and returns the ServerTime to use as ?since= next.</summary>
    private static async Task<string> SinceAsync(HttpClient client, string truck)
    {
        var first = await client.GetFromJsonAsync<DeliveriesResponse>($"/api/v1/trucks/{truck}/deliveries", Json);
        Assert.Empty(first!.Removed); // never anything removed in a full list
        return Uri.EscapeDataString(first.ServerTime.ToString("O"));
    }

    private static async Task<DeliveriesResponse> ChangesAsync(HttpClient client, string truck, string since) =>
        (await client.GetFromJsonAsync<DeliveriesResponse>($"/api/v1/trucks/{truck}/deliveries?since={since}", Json))!;

    [Fact]
    public async Task A_delivery_moved_to_another_truck_leaves_the_old_one_and_reaches_the_new_one()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();
        var sinceOld = await SinceAsync(client, "AB-1234");
        var sinceNew = await SinceAsync(client, "TG-5821");

        await MoveAsync(api, "TG-5821");

        // The old truck: told to remove it, and it is not in its list any more
        var old = await ChangesAsync(client, "AB-1234", sinceOld);
        Assert.Equal(new DeliveryKeyDto("QN2", "422211"), Assert.Single(old.Removed));
        Assert.DoesNotContain(old.Deliveries, d => d.Number == "422211");

        // The new truck: a new delivery for it, nothing removed
        var @new = await ChangesAsync(client, "TG-5821", sinceNew);
        Assert.Equal("TG-5821", Assert.Single(@new.Deliveries, d => d.Number == "422211").TruckPlate);
        Assert.Empty(@new.Removed);

        // The old truck's next question, after that answer: nothing more to do
        var later = await ChangesAsync(client, "AB-1234", Uri.EscapeDataString(old.ServerTime.ToString("O")));
        Assert.Empty(later.Removed);
    }

    [Fact]
    public async Task A_delivery_moved_away_and_back_is_simply_changed()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();
        var since = await SinceAsync(client, "AB-1234");

        await MoveAsync(api, "TG-5821");
        await MoveAsync(api, "AB-1234"); // the dispatcher changes their mind

        var changes = await ChangesAsync(client, "AB-1234", since);
        Assert.Empty(changes.Removed);
        Assert.Single(changes.Deliveries, d => d.Number == "422211");
    }

    [Fact]
    public async Task A_delivery_taken_off_every_truck_is_removed_from_the_old_one()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();
        var since = await SinceAsync(client, "AB-1234");

        await MoveAsync(api, truck: null);

        var changes = await ChangesAsync(client, "AB-1234", since);
        Assert.Equal("422211", Assert.Single(changes.Removed).Number);
    }

    [Fact]
    public async Task Unknown_truck_or_delivery_is_404()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();
        Assert.Equal(HttpStatusCode.NotFound,
            (await client.GetAsync("/api/v1/trucks/XX-0000/deliveries")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await client.GetAsync("/api/v1/deliveries/QN2/999999")).StatusCode);
    }

    [Fact]
    public async Task A_company_never_sees_another_companys_data()
    {
        using var api = await new TestApi().SeededAsync();
        await api.WithDbAsync(async db =>
        {
            var other = new Company { Id = Guid.NewGuid(), Code = "OTHER", Name = "Other Co" };
            var driver = new Driver { Id = Guid.NewGuid(), CompanyId = other.Id, Username = "other1", PinHash = "", DisplayName = "Other" };
            driver.PinHash = new PasswordHasher<Driver>().HashPassword(driver, "1111");
            db.AddRange(other, driver);
            await db.SaveChangesAsync();
        });
        var client = await api.LoggedInAsync("other1", "1111");

        Assert.Empty((await client.GetFromJsonAsync<List<VehicleDto>>("/api/v1/vehicles", Json))!);
        Assert.Equal(HttpStatusCode.NotFound,
            (await client.GetAsync("/api/v1/trucks/AB-1234/deliveries")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await client.GetAsync("/api/v1/deliveries/QN2/422211")).StatusCode);
    }

    [Fact]
    public async Task The_OpenAPI_contract_lists_the_endpoints()
    {
        using var api = await new TestApi().SeededAsync();
        var openApi = await api.CreateClient().GetStringAsync("/openapi/v1.json");
        Assert.Contains("/api/v1/auth/login", openApi);
        Assert.Contains("/api/v1/trucks/{plate}/deliveries", openApi);
        Assert.Contains("/api/v1/deliveries/{plantCode}/{number}", openApi);
    }
}
