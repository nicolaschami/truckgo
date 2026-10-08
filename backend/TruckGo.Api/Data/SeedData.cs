using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace TruckGo.Api.Data;

/// <summary>
/// Demo data for development and tests — the same trucks, plants and
/// deliveries as the app's mock data, so both sides show the same thing.
/// Drivers: <c>test1</c> / PIN <c>1234</c> and <c>test2</c> / PIN <c>5678</c>.
/// </summary>
public static class SeedData
{
    public const string CompanyCode = "DEMO";
    public const string DemoTruck = "AB-1234";

    public static async Task EnsureSeededAsync(TruckGoDb db, DateTime? now = null)
    {
        if (await db.Companies.AnyAsync()) return;
        var today = (now ?? DateTime.UtcNow).Date;
        DateTime At(int dayOffset, int hour, int minute) =>
            DateTime.SpecifyKind(today.AddDays(dayOffset).AddHours(hour).AddMinutes(minute), DateTimeKind.Utc);

        var company = new Company { Id = Guid.NewGuid(), Code = CompanyCode, Name = "TruckGo Demo" };
        db.Companies.Add(company);

        var hasher = new PasswordHasher<Driver>();
        foreach (var (user, pin, name) in new[] { ("test1", "1234", "Test Driver 1"), ("test2", "5678", "Test Driver 2") })
        {
            var driver = new Driver { Id = Guid.NewGuid(), CompanyId = company.Id, Username = user, PinHash = "", DisplayName = name };
            driver.PinHash = hasher.HashPassword(driver, pin);
            db.Drivers.Add(driver);
        }

        foreach (var (plate, truck, model, detail, status) in new[]
        {
            ("AB-1234", true, "Volvo FH16", "Tractor unit 6x4", VehicleStatus.Available),
            ("TG-5821", true, "Scania R500", "Tractor unit 4x2", VehicleStatus.Available),
            ("MN-7740", true, "Mercedes Actros", "Tractor unit 4x2", VehicleStatus.InUse),
            ("RT-3092", true, "DAF XF 480", "Tractor unit 6x2", VehicleStatus.Available),
            ("KL-1188", true, "MAN TGX", "Tractor unit 4x2", VehicleStatus.Maintenance),
            ("ZX-9054", true, "Iveco S-Way", "Tractor unit 4x2", VehicleStatus.Available),
            ("PL-4417", true, "Renault T High", "Tractor unit 4x2", VehicleStatus.InUse),
            ("BC-2260", true, "Volvo FM", "Rigid 8x4", VehicleStatus.Available),
            ("TR-1001", false, "Curtainsider", "34 pallets", VehicleStatus.Available),
            ("TR-1002", false, "Refrigerated", "33 pallets, -25 C", VehicleStatus.Available),
            ("TR-1003", false, "Flatbed", "27 t payload", VehicleStatus.InUse),
            ("TR-1004", false, "Tanker", "30,000 L", VehicleStatus.Available),
            ("TR-1005", false, "Container chassis", "40 ft", VehicleStatus.Available),
            ("TR-1006", false, "Box trailer", "90 m3", VehicleStatus.Maintenance),
        })
        {
            db.Vehicles.Add(new Vehicle
            {
                Id = Guid.NewGuid(), CompanyId = company.Id, Plate = plate, IsTruck = truck,
                Model = model, Detail = detail, Status = status,
            });
        }

        // Placeholder plant positions (same as the app)
        var north = new Plant { Id = Guid.NewGuid(), CompanyId = company.Id, Code = "QN2", Name = "Quarry North - Plant 2", Latitude = 52.5545, Longitude = -1.5260 };
        var south = new Plant { Id = Guid.NewGuid(), CompanyId = company.Id, Code = "QS1", Name = "Quarry South - Plant 1", Latitude = 52.2600, Longitude = -1.3935 };
        db.Plants.AddRange(north, south);

        Delivery New(Plant plant, string number, string order, string soldToCode, string soldTo,
            string shipTo, string address, double lat, double lng, string contact, string phone,
            string material, double tons, DateTime scheduled, int windowBefore, int windowAfter,
            double km, string? notes, DeliveryStatus status = DeliveryStatus.Assigned) => new()
        {
            Id = Guid.NewGuid(), CompanyId = company.Id, PlantId = plant.Id, Number = number,
            OrderNumber = order, TruckPlate = DemoTruck, SoldToCode = soldToCode, SoldToName = soldTo,
            ShipToName = shipTo, ShipToAddress = address, SiteLatitude = lat, SiteLongitude = lng,
            SiteContact = contact, SitePhone = phone, Material = material, OrderedTons = tons,
            ScheduledAt = scheduled, WindowStart = scheduled.AddMinutes(-windowBefore),
            WindowEnd = scheduled.AddMinutes(windowAfter), DistanceKm = km, Notes = notes,
            Status = status, UpdatedAt = DateTime.UtcNow,
        };

        // Current deliveries
        db.Deliveries.AddRange(
            New(north, "422211", "30771239", "100245", "Northgate Construction Ltd", "Riverside Arena Works",
                "Arena Way, Coventry", 52.4486, -1.4955, "Dan Whitfield  •  +44 7700 900123", "+447700900123",
                "AC 32 dense base 40/60", 20.00, At(0, 8, 0), 20, 20, 22.8,
                "Call the site foreman 15 minutes before arrival."),
            New(north, "422215", "30771402", "100318", "Harlow & Sons Civil Engineering", "Ring Road Resurfacing",
                "Ring Road, Warwick", 52.282, -1.5849, "Priya Nair  •  +44 7700 900456", "+447700900456",
                "AC 20 close surface 100/150", 18.50, At(0, 8, 53), 13, 22, 31.4, null),
            New(south, "422214", "30771388", "100577", "Metro Paving Services", "Station Car Park",
                "Station Road, Rugby", 52.3785, -1.2503, "Tom Hale  •  +44 7700 900789", "+447700900789",
                "SMA 14 surface", 22.00, At(0, 9, 46), 16, 24, 40.1,
                "Narrow access. Reverse in from the north entrance."));

        // History, with their weighbridge readings
        var h1 = New(north, "421987", "30769950", "100245", "Northgate Construction Ltd", "Riverside Arena Works",
            "Arena Way, Coventry", 52.4486, -1.4955, "Dan Whitfield  •  +44 7700 900123", "+447700900123",
            "AC 32 dense base 40/60", 20.00, At(-1, 14, 10), 20, 20, 22.8, null, DeliveryStatus.Delivered);
        var h2 = New(north, "421950", "30769811", "100318", "Harlow & Sons Civil Engineering", "Ring Road Resurfacing",
            "Ring Road, Warwick", 52.282, -1.5849, "Priya Nair  •  +44 7700 900456", "+447700900456",
            "AC 20 close surface 100/150", 20.00, At(-1, 10, 30), 20, 20, 31.4, null, DeliveryStatus.Delivered);
        foreach (var (d, gross) in new[] { (h1, 34.24), (h2, 34.00) })
        {
            d.Weighings.Add(new Weighing { Id = Guid.NewGuid(), Kind = WeighingKind.First, Tons = 14.20, WeighedAt = d.ScheduledAt.AddMinutes(-60), TicketNumber = $"T-{d.Number}-1", Weighbridge = "WB-1" });
            d.Weighings.Add(new Weighing { Id = Guid.NewGuid(), Kind = WeighingKind.Second, Tons = gross, WeighedAt = d.ScheduledAt.AddMinutes(-45), TicketNumber = $"T-{d.Number}-2", Weighbridge = "WB-1" });
        }
        db.Deliveries.AddRange(h1, h2);

        await db.SaveChangesAsync();
    }
}
