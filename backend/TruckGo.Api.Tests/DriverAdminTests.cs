using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Extensions.DependencyInjection;
using TruckGo.Admin;
using TruckGo.Api.Auth;

namespace TruckGo.Api.Tests;

/// <summary>
/// Driver accounts (screen 4): the back office creates them with a generated
/// PIN, and the app makes the driver choose their own (TruckGo.Core/Admin).
/// </summary>
public class DriverAdminTests
{
    [Fact]
    public async Task A_new_driver_gets_a_4_digit_PIN_and_must_change_it()
    {
        using var db = await TestDb.SeededAsync();
        var drivers = new DriverAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();

        var pin = await drivers.CreateAsync(company, " Juan01 ", "Juan Pérez", "+34 600 000 001");
        Assert.Matches("^[0-9]{4}$", pin);

        var juan = (await drivers.ListAsync(company)).Single(d => d.Username == "juan01"); // stored in lower case
        Assert.True(juan.MustChangePin);
        Assert.Equal("+34 600 000 001", juan.Phone);

        await drivers.ChangePinAsync(juan.Id, pin, pin == "2580" ? "3691" : "2580");
        Assert.False((await drivers.ListAsync(company)).Single(d => d.Id == juan.Id).MustChangePin);
    }

    [Fact]
    public async Task Refused_requests_explain_why()
    {
        using var db = await TestDb.SeededAsync();
        var drivers = new DriverAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();
        var test1 = (await drivers.ListAsync(company)).Single(d => d.Username == "test1");

        await AssertRefused("already used", () => drivers.CreateAsync(company, "TEST1", "Copy", null));
        await AssertRefused("letters or digits", () => drivers.CreateAsync(company, "juan pérez", "Juan", null));
        await AssertRefused("not correct", () => drivers.ChangePinAsync(test1.Id, "0000", "4821"));
        await AssertRefused("exactly 4 digits", () => drivers.ChangePinAsync(test1.Id, "1234", "12a4"));
        await AssertRefused("same digit", () => drivers.ChangePinAsync(test1.Id, "1234", "7777"));
        await AssertRefused("different", () => drivers.ChangePinAsync(test1.Id, "1234", "1234"));
    }

    [Fact]
    public async Task Reset_gives_a_new_PIN_unlocks_and_deactivated_drivers_stay_listed()
    {
        using var db = await TestDb.SeededAsync();
        var drivers = new DriverAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();
        var test2 = (await drivers.ListAsync(company)).Single(d => d.Username == "test2");

        var pin = await drivers.ResetPinAsync(company, test2.Id);
        Assert.Matches("^[0-9]{4}$", pin);
        Assert.True((await drivers.ListAsync(company)).Single(d => d.Id == test2.Id).MustChangePin);

        await drivers.SetActiveAsync(company, test2.Id, false);
        Assert.False((await drivers.ListAsync(company)).Single(d => d.Id == test2.Id).IsActive); // never deleted

        await AssertRefused("does not exist", () => drivers.ResetPinAsync(Guid.NewGuid(), test2.Id)); // other company
    }

    [Fact]
    public async Task The_app_is_told_to_change_the_PIN_and_can_do_it()
    {
        using var api = await new TestApi().SeededAsync();

        // The office creates a driver; the app logs in with the generated PIN
        string pin = "";
        await api.ImportAsync(async (_, company) =>
        {
            using var scope = api.Services.CreateScope();
            pin = await scope.ServiceProvider.GetRequiredService<DriverAdmin>().CreateAsync(company, "newdriver", "New Driver", null);
        });
        var client = api.CreateClient();
        var login = await (await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest("NewDriver", pin, "phone-9")))
            .Content.ReadFromJsonAsync<LoginResponse>();
        Assert.True(login!.MustChangePin);

        // The app sends the new PIN
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
        var newPin = pin == "4821" ? "5932" : "4821";
        Assert.Equal(HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/auth/change-pin", new ChangePinRequest(pin, "11"))).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent,
            (await client.PostAsJsonAsync("/api/v1/auth/change-pin", new ChangePinRequest(pin, newPin))).StatusCode);

        // Next login: new PIN works, no change asked any more
        var again = await (await api.CreateClient().PostAsJsonAsync("/api/v1/auth/login", new LoginRequest("newdriver", newPin, null)))
            .Content.ReadFromJsonAsync<LoginResponse>();
        Assert.False(again!.MustChangePin);
    }

    private static async Task AssertRefused(string expected, Func<Task> action)
    {
        var e = await Assert.ThrowsAsync<AdminException>(action);
        Assert.Contains(expected, e.Message, StringComparison.OrdinalIgnoreCase);
    }
}
