using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Api.Tests;

/// <summary>
/// A private in-memory SQLite database with the demo data, handed out as a
/// context factory — the way the back office reaches the database. For
/// testing TruckGo.Core logic without starting a web site.
/// </summary>
public sealed class TestDb : IDbContextFactory<TruckGoDb>, IDisposable
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");
    private readonly DbContextOptions<TruckGoDb> _options;

    private TestDb()
    {
        _connection.Open();
        _options = new DbContextOptionsBuilder<TruckGoDb>().UseSqlite(_connection).Options;
    }

    public static async Task<TestDb> SeededAsync()
    {
        var testDb = new TestDb();
        await using var db = testDb.CreateDbContext();
        await db.Database.EnsureCreatedAsync();
        await SeedData.EnsureSeededAsync(db);
        return testDb;
    }

    public TruckGoDb CreateDbContext() => new(_options);

    /// <summary>The demo company's id.</summary>
    public async Task<Guid> DemoCompanyAsync()
    {
        await using var db = CreateDbContext();
        return (await db.Companies.SingleAsync(c => c.Code == SeedData.CompanyCode)).Id;
    }

    public void Dispose() => _connection.Dispose();
}
