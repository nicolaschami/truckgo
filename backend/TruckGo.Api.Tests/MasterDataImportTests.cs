using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using TruckGo.Data;
using TruckGo.Api.Deliveries;
using TruckGo.Integration;

namespace TruckGo.Api.Tests;

/// <summary>
/// The save step for master data (Integration/MasterDataImport.cs): what the
/// other system sends, and what the app then sees.
/// </summary>
public class MasterDataImportTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    [Fact]
    public async Task Same_code_twice_updates_the_record_instead_of_adding_one()
    {
        using var api = await new TestApi().SeededAsync();

        await api.ImportAsync(async (import, company) =>
        {
            await import.SaveCustomerAsync(company, new CustomerMessage("200001", "First Name Ltd", City: "Rugby"));
            await import.SaveCustomerAsync(company, new CustomerMessage("200001", "Renamed Ltd", City: "Rugby",
                IsActive: false, Extra: new() { ["Account manager"] = "J. Smith" }));
        });

        await api.WithDbAsync(async db =>
        {
            var customer = await db.Customers.SingleAsync(c => c.ExternalCode == "200001");
            Assert.Equal("Renamed Ltd", customer.Name);
            Assert.False(customer.IsActive);
            Assert.Equal("J. Smith", customer.Extra["Account manager"]); // extra info survives the JSON column
            Assert.True(customer.LastReceivedAt > DateTime.UtcNow.AddMinutes(-1));
        });
    }

    [Fact]
    public async Task A_record_pointing_to_something_never_received_is_refused()
    {
        using var api = await new TestApi().SeededAsync();

        await api.ImportAsync(async (import, company) =>
        {
            var noCustomer = await Assert.ThrowsAsync<MasterDataException>(() =>
                import.SaveShipToAsync(company, new ShipToMessage("X-01", "NO-SUCH-CUSTOMER", "Site", 52, -1)));
            Assert.Contains("unknown customer NO-SUCH-CUSTOMER", noCustomer.Message);

            var noAgent = await Assert.ThrowsAsync<MasterDataException>(() =>
                import.SaveVehicleAsync(company, new VehicleMessage("ZZ-1", "ZZ-1", VehicleKind.Truck, "Volvo", ForwardingAgentCode: "FA-99")));
            Assert.Contains("unknown forwarding agent FA-99", noAgent.Message);

            // A ship-to of another customer
            var wrongShipTo = await Assert.ThrowsAsync<MasterDataException>(() =>
                import.SaveDeliveryAsync(company, new DeliveryMessage("QN2", "500001", "1", "100245", "100318-01",
                    "Sand", 10, DateTime.UtcNow, DateTime.UtcNow, DateTime.UtcNow)));
            Assert.Contains("does not belong to customer 100245", wrongShipTo.Message);
        });
    }

    [Fact]
    public async Task A_corrected_ship_to_location_also_fixes_its_open_deliveries()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        // The other system moves Riverside Arena Works a little
        await api.ImportAsync((import, company) => import.SaveShipToAsync(company,
            new ShipToMessage("100245-01", "100245", "Riverside Arena Works", 52.4500, -1.5000,
                Address: "Arena Way", City: "Coventry", ContactName: "Dan Whitfield", ContactPhone: "+44 7700 900123")));

        var delivery = await client.GetFromJsonAsync<DeliveryDto>("/api/v1/deliveries/QN2/422211", Json);
        Assert.Equal(52.4500, delivery!.SiteLatitude);
        Assert.Equal(-1.5000, delivery.SiteLongitude);
    }

    [Fact]
    public async Task Cancelling_works_but_never_undoes_a_delivered_one()
    {
        using var api = await new TestApi().SeededAsync();

        await api.ImportAsync(async (import, company) =>
        {
            DeliveryMessage Cancel(string number) => new("QN2", number, "x", "100245", "100245-01",
                "AC 32", 20, DateTime.UtcNow, DateTime.UtcNow, DateTime.UtcNow, IsCancelled: true);

            Assert.Equal(DeliveryStatus.Cancelled, (await import.SaveDeliveryAsync(company, Cancel("422211"))).Status);
            Assert.Equal(DeliveryStatus.Delivered, (await import.SaveDeliveryAsync(company, Cancel("421987"))).Status);
        });
    }

    [Fact]
    public async Task Both_geofences_use_the_one_radius_setting()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        // The Admin changes the setting from 200 m to 350 m
        await api.WithDbAsync(async db =>
        {
            (await db.Settings.SingleAsync()).GeofenceRadiusM = 350;
            await db.SaveChangesAsync();
        });

        var delivery = await client.GetFromJsonAsync<DeliveryDto>("/api/v1/deliveries/QN2/422211", Json);
        Assert.Equal(350, delivery!.PlantGeofenceRadiusM);
        Assert.Equal(350, delivery.SiteGeofenceRadiusM);
    }

    [Fact]
    public async Task A_truck_on_a_started_delivery_is_in_use_and_inactive_vehicles_are_hidden()
    {
        using var api = await new TestApi().SeededAsync();
        var client = await api.LoggedInAsync();

        await api.WithDbAsync(async db =>
        {
            // The demo truck has entered the plant for 422211
            (await db.Deliveries.SingleAsync(d => d.Number == "422211")).Status = DeliveryStatus.AtPlant;
            await db.SaveChangesAsync();
        });
        // The other system deactivates a trailer
        await api.ImportAsync((import, company) => import.SaveVehicleAsync(company,
            new VehicleMessage("TR-1006", "TR-1006", VehicleKind.Trailer, "Box trailer", IsActive: false)));

        var vehicles = (await client.GetFromJsonAsync<List<VehicleDto>>("/api/v1/vehicles", Json))!;
        Assert.Equal(VehicleStatus.InUse, vehicles.Single(v => v.Plate == SeedData.DemoTruck).Status);
        Assert.Equal(VehicleStatus.InUse, vehicles.Single(v => v.Plate == SeedData.DemoTrailer).Status);
        Assert.Equal(VehicleStatus.Available, vehicles.Single(v => v.Plate == "TG-5821").Status);
        Assert.DoesNotContain(vehicles, v => v.Plate == "TR-1006");
    }
}
