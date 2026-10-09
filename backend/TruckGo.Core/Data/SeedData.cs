using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using TruckGo.Integration;

namespace TruckGo.Data;

/// <summary>
/// Demo data for development and tests — the same trucks, plants and
/// deliveries as the app's mock data, so both sides show the same thing.
///
/// Until the real integration (SQS or API) exists, this is how master data
/// gets into the tables. It goes through MasterDataImport — the same door the
/// integration will use — so the data is saved exactly as it will be later.
///
/// Logins:
///   app drivers        test1 / PIN 1234,  test2 / PIN 5678
///   back office        superadmin@truckgo.local, admin@demo.truckgo.local,
///                      dispatcher@demo.truckgo.local, viewer@demo.truckgo.local
///                      — all with password Demo-1234
/// </summary>
public static class SeedData
{
    public const string CompanyCode = "DEMO";
    public const string DemoTruck = "AB-1234";
    public const string DemoTrailer = "TR-1001";
    public const string BackOfficePassword = "Demo-1234";

    public static async Task EnsureSeededAsync(TruckGoDb db, DateTime? now = null)
    {
        // Seed only an empty database
        if (await db.Companies.AnyAsync()) return;

        var today = (now ?? DateTime.UtcNow).Date;
        DateTime At(int dayOffset, int hour, int minute) =>
            DateTime.SpecifyKind(today.AddDays(dayOffset).AddHours(hour).AddMinutes(minute), DateTimeKind.Utc);

        // ---- TruckGo's own data: company, settings, logins ----

        var company = new Company { Id = Guid.NewGuid(), Code = CompanyCode, Name = "TruckGo Demo" };
        db.Companies.Add(company);
        db.Settings.Add(new CompanySettings { CompanyId = company.Id }); // all defaults (200 m...)

        // Demo drivers do not have to change their PIN, so the app tests stay simple
        var pinHasher = new PasswordHasher<Driver>();
        foreach (var (user, pin, name, phone) in new[]
        {
            ("test1", "1234", "Test Driver 1", "+44 7700 900001"),
            ("test2", "5678", "Test Driver 2", "+44 7700 900002"),
        })
        {
            var driver = new Driver { Id = Guid.NewGuid(), CompanyId = company.Id, Username = user, PinHash = "", DisplayName = name, Phone = phone };
            driver.PinHash = pinHasher.HashPassword(driver, pin);
            db.Drivers.Add(driver);
        }

        // One back-office user per role
        var passwordHasher = new PasswordHasher<BackOfficeUser>();
        foreach (var (email, name, role) in new[]
        {
            ("superadmin@truckgo.local", "TruckGo Super Admin", UserRole.SuperAdmin),
            ("admin@demo.truckgo.local", "Demo Admin", UserRole.Admin),
            ("dispatcher@demo.truckgo.local", "Demo Dispatcher", UserRole.Dispatcher),
            ("viewer@demo.truckgo.local", "Demo Viewer", UserRole.Viewer),
        })
        {
            var user = new BackOfficeUser
            {
                Id = Guid.NewGuid(),
                CompanyId = role == UserRole.SuperAdmin ? null : company.Id, // a super admin has no company
                Email = email, PasswordHash = "", DisplayName = name, Role = role,
            };
            user.PasswordHash = passwordHasher.HashPassword(user, BackOfficePassword);
            db.Users.Add(user);
        }

        await db.SaveChangesAsync();

        // ---- Master data, through the integration's door ----
        // Order matters: a record can only point to records already received.

        var import = new MasterDataImport(db, TimeProvider.System);
        var c = company.Id;

        // Plants (placeholder positions, same as the app)
        await import.SavePlantAsync(c, new PlantMessage("QN2", "Quarry North - Plant 2", 52.5545, -1.5260,
            Address: "Quarry Lane", City: "Nuneaton", Postcode: "CV10 0AA", Country: "GB", Phone: "+44 24 7600 0002"));
        await import.SavePlantAsync(c, new PlantMessage("QS1", "Quarry South - Plant 1", 52.2600, -1.3935,
            Address: "Southam Road", City: "Southam", Postcode: "CV47 0AA", Country: "GB", Phone: "+44 1926 000001"));

        // Forwarding agents
        await import.SaveForwardingAgentAsync(c, new ForwardingAgentMessage("FA-01", "Midlands Haulage Ltd",
            Address: "Unit 4, Foleshill Road", City: "Coventry", Postcode: "CV6 5AA", Country: "GB",
            Phone: "+44 24 7600 1111", Email: "planning@midlandshaulage.example", TaxId: "GB123456789"));
        await import.SaveForwardingAgentAsync(c, new ForwardingAgentMessage("FA-02", "Warwick Tippers",
            Address: "Budbrooke Industrial Estate", City: "Warwick", Postcode: "CV34 5AA", Country: "GB",
            Phone: "+44 1926 222222", Email: "office@warwicktippers.example"));

        // Trucks and trailers (the code in the other system is the plate here).
        // The last two trucks have no forwarding agent: the agent is optional.
        foreach (var (plate, kind, model, description, agent) in new[]
        {
            ("AB-1234", VehicleKind.Truck, "Volvo FH16", "Tractor unit 6x4", "FA-01"),
            ("TG-5821", VehicleKind.Truck, "Scania R500", "Tractor unit 4x2", "FA-01"),
            ("MN-7740", VehicleKind.Truck, "Mercedes Actros", "Tractor unit 4x2", "FA-01"),
            ("RT-3092", VehicleKind.Truck, "DAF XF 480", "Tractor unit 6x2", "FA-02"),
            ("KL-1188", VehicleKind.Truck, "MAN TGX", "Tractor unit 4x2", "FA-02"),
            ("ZX-9054", VehicleKind.Truck, "Iveco S-Way", "Tractor unit 4x2", "FA-02"),
            ("PL-4417", VehicleKind.Truck, "Renault T High", "Tractor unit 4x2", null),
            ("BC-2260", VehicleKind.Truck, "Volvo FM", "Rigid 8x4", null),
            ("TR-1001", VehicleKind.Trailer, "Curtainsider", "34 pallets", "FA-01"),
            ("TR-1002", VehicleKind.Trailer, "Refrigerated", "33 pallets, -25 C", "FA-01"),
            ("TR-1003", VehicleKind.Trailer, "Flatbed", "27 t payload", "FA-01"),
            ("TR-1004", VehicleKind.Trailer, "Tanker", "30,000 L", "FA-02"),
            ("TR-1005", VehicleKind.Trailer, "Container chassis", "40 ft", "FA-02"),
            ("TR-1006", VehicleKind.Trailer, "Box trailer", "90 m3", "FA-02"),
        })
        {
            await import.SaveVehicleAsync(c, new VehicleMessage(plate, plate, kind, model, description, agent));
        }

        // Customers and their ship-tos
        await import.SaveCustomerAsync(c, new CustomerMessage("100245", "Northgate Construction Ltd",
            Address: "1 Northgate House", City: "Coventry", Postcode: "CV1 1AA", Country: "GB", Phone: "+44 24 7600 2450", TaxId: "GB100245000"));
        await import.SaveShipToAsync(c, new ShipToMessage("100245-01", "100245", "Riverside Arena Works", 52.4486, -1.4955,
            Address: "Arena Way", City: "Coventry", Postcode: "CV6 6AA", Country: "GB",
            ContactName: "Dan Whitfield", ContactPhone: "+44 7700 900123",
            DeliveryInstructions: "Use the north gate. Hard hat and hi-vis required.", OpeningHours: "Mon-Fri 07:00-17:00",
            Extra: new() { ["Gate code"] = "4512" }));
        await import.SaveShipToAsync(c, new ShipToMessage("100245-02", "100245", "Canal Basin Apartments", 52.4129, -1.5106,
            Address: "Leicester Row", City: "Coventry", Postcode: "CV1 4AA", Country: "GB",
            ContactName: "Sara Mills", ContactPhone: "+44 7700 900124", OpeningHours: "Mon-Sat 07:30-16:00"));

        await import.SaveCustomerAsync(c, new CustomerMessage("100318", "Harlow & Sons Civil Engineering",
            Address: "Harlow Yard, Myton Road", City: "Warwick", Postcode: "CV34 6AA", Country: "GB", Phone: "+44 1926 318318"));
        await import.SaveShipToAsync(c, new ShipToMessage("100318-01", "100318", "Ring Road Resurfacing", 52.282, -1.5849,
            Address: "Ring Road", City: "Warwick", Postcode: "CV34 4AA", Country: "GB",
            ContactName: "Priya Nair", ContactPhone: "+44 7700 900456", OpeningHours: "Night works 20:00-06:00"));

        await import.SaveCustomerAsync(c, new CustomerMessage("100577", "Metro Paving Services",
            Address: "7 Dunchurch Road", City: "Rugby", Postcode: "CV22 6AA", Country: "GB", Phone: "+44 1788 577577"));
        await import.SaveShipToAsync(c, new ShipToMessage("100577-01", "100577", "Station Car Park", 52.3785, -1.2503,
            Address: "Station Road", City: "Rugby", Postcode: "CV21 3AA", Country: "GB",
            ContactName: "Tom Hale", ContactPhone: "+44 7700 900789",
            DeliveryInstructions: "Narrow access. Reverse in from the north entrance."));

        // An inactive customer, to show the "active only" filter of the screens
        await import.SaveCustomerAsync(c, new CustomerMessage("100999", "Old Mill Builders (closed)",
            City: "Leamington Spa", Country: "GB", IsActive: false));
        await import.SaveShipToAsync(c, new ShipToMessage("100999-01", "100999", "Old Mill Site", 52.2852, -1.5363,
            City: "Leamington Spa", Country: "GB", IsActive: false));

        // Deliveries of the demo truck, today (all still Assigned)
        DeliveryMessage New(string plant, string number, string order, string customer, string shipTo,
            string material, double tons, DateTime scheduled, int windowBefore, int windowAfter,
            double km, string? notes) => new(
                plant, number, order, customer, shipTo, material, tons,
                scheduled, scheduled.AddMinutes(-windowBefore), scheduled.AddMinutes(windowAfter),
                DemoTruck, DemoTrailer, km, notes);

        await import.SaveDeliveryAsync(c, New("QN2", "422211", "30771239", "100245", "100245-01",
            "AC 32 dense base 40/60", 20.00, At(0, 8, 0), 20, 20, 22.8,
            "Call the site foreman 15 minutes before arrival."));
        await import.SaveDeliveryAsync(c, New("QN2", "422215", "30771402", "100318", "100318-01",
            "AC 20 close surface 100/150", 18.50, At(0, 8, 53), 13, 22, 31.4, null));
        await import.SaveDeliveryAsync(c, New("QS1", "422214", "30771388", "100577", "100577-01",
            "SMA 14 surface", 22.00, At(0, 9, 46), 16, 24, 40.1,
            "Narrow access. Reverse in from the north entrance."));

        // Yesterday's deliveries, with their weighbridge readings
        var history = new[]
        {
            (New("QN2", "421987", "30769950", "100245", "100245-01", "AC 32 dense base 40/60", 20.00, At(-1, 14, 10), 20, 20, 22.8, null), Gross: 34.24),
            (New("QN2", "421950", "30769811", "100318", "100318-01", "AC 20 close surface 100/150", 20.00, At(-1, 10, 30), 20, 20, 31.4, null), Gross: 34.00),
        };
        foreach (var (message, gross) in history)
        {
            var delivery = await import.SaveDeliveryAsync(c, message);
            await import.SaveWeighingAsync(c, new WeighingMessage(message.PlantCode, message.Number, WeighingKind.First,
                14.20, message.ScheduledAt.AddMinutes(-60), $"T-{message.Number}-1", "WB-1"));
            await import.SaveWeighingAsync(c, new WeighingMessage(message.PlantCode, message.Number, WeighingKind.Second,
                gross, message.ScheduledAt.AddMinutes(-45), $"T-{message.Number}-2", "WB-1"));

            // In real life the app moves a delivery to Delivered; the demo
            // data sets it directly so the history looks finished
            delivery.Status = DeliveryStatus.Delivered;
        }
        await db.SaveChangesAsync();
    }
}
