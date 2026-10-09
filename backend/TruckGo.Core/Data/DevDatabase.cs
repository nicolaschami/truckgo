using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace TruckGo.Data;

/// <summary>
/// Development only: brings the local database up to date and loads the demo
/// data. Both the API and the back office call it at start-up, so whichever
/// you start first creates the database. Never used in production, where
/// migrations are applied on purpose.
/// </summary>
public static class DevDatabase
{
    public static async Task MigrateAndSeedAsync(IServiceProvider services)
    {
        using var scope = services.CreateScope();
        // The API registers a context, the back office a context factory
        await using var db = scope.ServiceProvider.GetService<IDbContextFactory<TruckGoDb>>() is { } factory
            ? await factory.CreateDbContextAsync()
            : scope.ServiceProvider.GetRequiredService<TruckGoDb>();
        await db.Database.MigrateAsync();
        await SeedData.EnsureSeededAsync(db);
    }
}
