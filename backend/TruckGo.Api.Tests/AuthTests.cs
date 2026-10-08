using System.Net;
using System.Net.Http.Json;
using TruckGo.Api.Auth;

namespace TruckGo.Api.Tests;

public class AuthTests
{
    [Fact]
    public async Task Login_with_the_right_PIN_returns_a_token_and_the_driver()
    {
        using var api = await new TestApi().SeededAsync();
        var response = await api.CreateClient().PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest("test1", "1234", "phone-1"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var login = await response.Content.ReadFromJsonAsync<LoginResponse>();
        Assert.False(string.IsNullOrEmpty(login!.AccessToken));
        Assert.Equal("test1", login.Driver.Username);
        Assert.Equal("DEMO", login.Driver.CompanyCode);
        Assert.True(login.ExpiresAt > DateTime.UtcNow.AddMinutes(30));
    }

    [Theory]
    [InlineData("test1", "0000")] // wrong PIN
    [InlineData("nobody", "1234")] // unknown user: same answer, reveals nothing
    public async Task Login_fails_with_401(string username, string pin)
    {
        using var api = await new TestApi().SeededAsync();
        var response = await api.CreateClient().PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(username, pin, null));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Five_wrong_PINs_lock_the_account()
    {
        using var api = await new TestApi().SeededAsync();
        var client = api.CreateClient();
        for (var i = 0; i < AuthEndpoints.MaxFailedLogins; i++)
            await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest("test1", "9999", null));

        // Even the right PIN is refused while locked
        var response = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest("test1", "1234", null));
        Assert.Equal(HttpStatusCode.Locked, response.StatusCode);
    }

    [Fact]
    public async Task Data_endpoints_need_a_token()
    {
        using var api = await new TestApi().SeededAsync();
        var response = await api.CreateClient().GetAsync("/api/v1/trucks/AB-1234/deliveries");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
