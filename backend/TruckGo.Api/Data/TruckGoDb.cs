using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace TruckGo.Api.Data;

/// <summary>
/// The TruckGo database (PostgreSQL in real life, SQLite in the tests).
/// The tables and their meaning are described in Entities.cs.
/// </summary>
public class TruckGoDb(DbContextOptions<TruckGoDb> options) : DbContext(options)
{
    // TruckGo's own data
    public DbSet<Company> Companies => Set<Company>();
    public DbSet<CompanySettings> Settings => Set<CompanySettings>();
    public DbSet<Driver> Drivers => Set<Driver>();
    public DbSet<BackOfficeUser> Users => Set<BackOfficeUser>();

    // Master data, received from the other system
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<ShipTo> ShipTos => Set<ShipTo>();
    public DbSet<Plant> Plants => Set<Plant>();
    public DbSet<ForwardingAgent> ForwardingAgents => Set<ForwardingAgent>();
    public DbSet<Vehicle> Vehicles => Set<Vehicle>();
    public DbSet<Delivery> Deliveries => Set<Delivery>();
    public DbSet<Weighing> Weighings => Set<Weighing>();

    protected override void ConfigureConventions(ModelConfigurationBuilder builder)
    {
        // Enums stored as readable text ("InTransit"), dates always UTC
        builder.Properties<Enum>().HaveConversion<string>().HaveMaxLength(20);
        builder.Properties<DateTime>().HaveConversion<UtcConverter>();
        builder.Properties<DateTime?>().HaveConversion<NullableUtcConverter>();

        // "Extra info" is stored as a JSON text column, e.g. {"Gate code":"4512"}
        builder.Properties<Dictionary<string, string>>()
            .HaveConversion<ExtraConverter, ExtraComparer>();
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

        // --- TruckGo's own data ---

        model.Entity<Company>().HasIndex(c => c.Code).IsUnique();

        // One settings row per company; its key is the company id
        model.Entity<CompanySettings>(s =>
        {
            s.HasKey(x => x.CompanyId);
            s.HasOne<Company>().WithOne().HasForeignKey<CompanySettings>(x => x.CompanyId);
        });

        // Usernames and emails are unique on the whole server: a login does
        // not ask which company you belong to
        model.Entity<Driver>().HasIndex(d => d.Username).IsUnique();
        model.Entity<BackOfficeUser>().HasIndex(u => u.Email).IsUnique();

        // --- Master data: one record per external code inside a company ---

        model.Entity<Customer>().HasIndex(x => new { x.CompanyId, x.ExternalCode }).IsUnique();
        model.Entity<ShipTo>().HasIndex(x => new { x.CompanyId, x.ExternalCode }).IsUnique();
        model.Entity<Plant>().HasIndex(x => new { x.CompanyId, x.ExternalCode }).IsUnique();
        model.Entity<ForwardingAgent>().HasIndex(x => new { x.CompanyId, x.ExternalCode }).IsUnique();

        model.Entity<Vehicle>(v =>
        {
            v.HasIndex(x => new { x.CompanyId, x.ExternalCode }).IsUnique();
            v.HasIndex(x => new { x.CompanyId, x.Plate }).IsUnique();
            v.HasOne(x => x.ForwardingAgent).WithMany().OnDelete(DeleteBehavior.Restrict);
        });

        model.Entity<Delivery>(d =>
        {
            // The delivery key: plant + number
            d.HasIndex(x => new { x.PlantId, x.Number }).IsUnique();
            // For the app's "deliveries of my truck changed since..." call
            d.HasIndex(x => new { x.CompanyId, x.TruckPlate, x.UpdatedAt });
            d.HasMany(x => x.Weighings).WithOne().HasForeignKey(w => w.DeliveryId);

            // Master data is never deleted, but if someone tried, a customer
            // or ship-to with deliveries must not take them along
            d.HasOne(x => x.Customer).WithMany().OnDelete(DeleteBehavior.Restrict);
            d.HasOne(x => x.ShipTo).WithMany().OnDelete(DeleteBehavior.Restrict);
            d.HasOne(x => x.Plant).WithMany().OnDelete(DeleteBehavior.Restrict);
        });
    }

    // Npgsql needs UTC; SQLite (tests) loses the kind — always hand back UTC
    private class UtcConverter() : ValueConverter<DateTime, DateTime>(
        v => v.ToUniversalTime(),
        v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

    private class NullableUtcConverter() : ValueConverter<DateTime?, DateTime?>(
        v => v.HasValue ? v.Value.ToUniversalTime() : v,
        v => v.HasValue ? DateTime.SpecifyKind(v.Value, DateTimeKind.Utc) : v);

    // Extra info <-> JSON text. Plain text (not jsonb) so the same column
    // works on PostgreSQL and on SQLite in the tests.
    private class ExtraConverter() : ValueConverter<Dictionary<string, string>, string>(
        v => JsonSerializer.Serialize(v, (JsonSerializerOptions?)null),
        v => JsonSerializer.Deserialize<Dictionary<string, string>>(v, (JsonSerializerOptions?)null) ?? new());

    // Lets EF notice a change inside the dictionary (not only a new one)
    private class ExtraComparer() : ValueComparer<Dictionary<string, string>>(
        (a, b) => JsonSerializer.Serialize(a, (JsonSerializerOptions?)null) == JsonSerializer.Serialize(b, (JsonSerializerOptions?)null),
        v => JsonSerializer.Serialize(v, (JsonSerializerOptions?)null).GetHashCode(),
        v => new Dictionary<string, string>(v));
}
