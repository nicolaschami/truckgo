using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace TruckGo.Api.Data;

public class TruckGoDb(DbContextOptions<TruckGoDb> options) : DbContext(options)
{
    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Driver> Drivers => Set<Driver>();
    public DbSet<Vehicle> Vehicles => Set<Vehicle>();
    public DbSet<Plant> Plants => Set<Plant>();
    public DbSet<Delivery> Deliveries => Set<Delivery>();
    public DbSet<Weighing> Weighings => Set<Weighing>();

    protected override void ConfigureConventions(ModelConfigurationBuilder builder)
    {
        // Enums stored as readable text ("InTransit"), dates always UTC
        builder.Properties<Enum>().HaveConversion<string>().HaveMaxLength(20);
        builder.Properties<DateTime>().HaveConversion<UtcConverter>();
        builder.Properties<DateTime?>().HaveConversion<NullableUtcConverter>();
    }

    protected override void OnModelCreating(ModelBuilder model)
    {
        // Ids are always created by our code (Guid.NewGuid()). Telling EF so
        // makes a new row added to an existing delivery (e.g. a weighing) an
        // insert, not an update of a row that does not exist.
        foreach (var entity in model.Model.GetEntityTypes())
        {
            foreach (var key in entity.FindPrimaryKey()?.Properties ?? [])
            {
                if (key.ClrType == typeof(Guid)) key.ValueGenerated = Microsoft.EntityFrameworkCore.Metadata.ValueGenerated.Never;
            }
        }

        model.Entity<Company>().HasIndex(c => c.Code).IsUnique();

        model.Entity<Driver>().HasIndex(d => d.Username).IsUnique();

        model.Entity<Vehicle>().HasIndex(v => new { v.CompanyId, v.Plate }).IsUnique();

        model.Entity<Plant>().HasIndex(p => new { p.CompanyId, p.Code }).IsUnique();

        model.Entity<Delivery>(d =>
        {
            d.HasIndex(x => new { x.PlantId, x.Number }).IsUnique();
            d.HasIndex(x => new { x.CompanyId, x.TruckPlate, x.UpdatedAt });
            d.HasMany(x => x.Weighings).WithOne().HasForeignKey(w => w.DeliveryId);
        });
    }

    // Npgsql needs UTC; SQLite (tests) loses the kind — always hand back UTC
    private class UtcConverter() : ValueConverter<DateTime, DateTime>(
        v => v.ToUniversalTime(),
        v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

    private class NullableUtcConverter() : ValueConverter<DateTime?, DateTime?>(
        v => v.HasValue ? v.Value.ToUniversalTime() : v,
        v => v.HasValue ? DateTime.SpecifyKind(v.Value, DateTimeKind.Utc) : v);
}
