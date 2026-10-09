using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using TruckGo.Api.Auth;
using TruckGo.Data;
using TruckGo.Integration;

namespace TruckGo.Api.Tests;

/// <summary>
/// The whole API in memory, on a private SQLite database with the demo data,
/// so the tests need neither PostgreSQL nor a network.
/// </summary>
public sealed class TestApi : WebApplicationFactory<Program>
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");

    public TestApi() => _connection.Open();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development"); // for the OpenAPI document
        builder.ConfigureAppConfiguration(c => c.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Database:MigrateAndSeed"] = "false", // the tests create their own database
            ["Jwt:SigningKey"] = "test-signing-key-0123456789abcdef0123456789",
        }));
        builder.ConfigureServices(services =>
        {
            // Replace PostgreSQL with the in-memory SQLite database
            services.RemoveAll<DbContextOptions<TruckGoDb>>();
            services.RemoveAll<IDbContextOptionsConfiguration<TruckGoDb>>();
            services.AddDbContext<TruckGoDb>(o => o.UseSqlite(_connection));
        });
    }

    public async Task<TestApi> SeededAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<TruckGoDb>();
        await db.Database.EnsureCreatedAsync();
        await SeedData.EnsureSeededAsync(db);
        return this;
    }

    public async Task WithDbAsync(Func<TruckGoDb, Task> work)
    {
        using var scope = Services.CreateScope();
        await work(scope.ServiceProvider.GetRequiredService<TruckGoDb>());
    }

    /// <summary>
    /// Sends master data through the integration's door (MasterDataImport),
    /// as the other system will. Hands over the demo company's id.
    /// </summary>
    public async Task ImportAsync(Func<MasterDataImport, Guid, Task> work)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<TruckGoDb>();
        var company = await db.Companies.SingleAsync(c => c.Code == SeedData.CompanyCode);
        await work(scope.ServiceProvider.GetRequiredService<MasterDataImport>(), company.Id);
    }

    /// <summary>A client logged in as <paramref name="username"/>.</summary>
    public async Task<HttpClient> LoggedInAsync(string username = "test1", string pin = "1234")
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(username, pin, "test-device"));
        response.EnsureSuccessStatusCode();
        var login = await response.Content.ReadFromJsonAsync<LoginResponse>();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", login!.AccessToken);
        return client;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) _connection.Dispose();
    }
}
