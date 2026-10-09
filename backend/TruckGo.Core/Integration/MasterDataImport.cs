using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Integration;

/// <summary>
/// THE ONE DOOR for master data into TruckGo: one "save" method per record
/// type. The seed data uses it today; an SQS queue or an API will use the very
/// same methods later, so choosing the transport changes nothing here.
///
/// Every save works the same way:
///   1. look the record up by its external code (inside the company);
///   2. not found → create it; found → overwrite every received field;
///   3. stamp LastReceivedAt, save.
/// One call = one message = one database transaction.
///
/// Fields TruckGo owns (statuses from the app, settings...) are never touched
/// here. References to other records must already exist, otherwise a
/// MasterDataException explains what is missing.
/// </summary>
public class MasterDataImport(TruckGoDb db, TimeProvider clock)
{
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    public async Task<Customer> SaveCustomerAsync(Guid companyId, CustomerMessage m)
    {
        var row = await db.Customers.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.Code)
            ?? Add(db.Customers, new Customer { Id = Guid.NewGuid(), CompanyId = companyId, ExternalCode = m.Code, Name = m.Name });

        row.Name = m.Name;
        row.Address = m.Address;
        row.City = m.City;
        row.Postcode = m.Postcode;
        row.Country = m.Country;
        row.Phone = m.Phone;
        row.TaxId = m.TaxId;
        Stamp(row, m.IsActive, m.Extra);

        await db.SaveChangesAsync();
        return row;
    }

    public async Task<ShipTo> SaveShipToAsync(Guid companyId, ShipToMessage m)
    {
        // The customer must have been received first
        var customer = await db.Customers.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.CustomerCode)
            ?? throw new MasterDataException($"Ship-to {m.Code}: unknown customer {m.CustomerCode}.");

        var row = await db.ShipTos.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.Code)
            ?? Add(db.ShipTos, new ShipTo { Id = Guid.NewGuid(), CompanyId = companyId, ExternalCode = m.Code, Name = m.Name });

        row.CustomerId = customer.Id;
        row.Name = m.Name;
        row.Address = m.Address;
        row.City = m.City;
        row.Postcode = m.Postcode;
        row.Country = m.Country;
        row.Latitude = m.Latitude;
        row.Longitude = m.Longitude;
        row.ContactName = m.ContactName;
        row.ContactPhone = m.ContactPhone;
        row.DeliveryInstructions = m.DeliveryInstructions;
        row.OpeningHours = m.OpeningHours;
        Stamp(row, m.IsActive, m.Extra);

        await db.SaveChangesAsync();
        return row;
    }

    public async Task<Plant> SavePlantAsync(Guid companyId, PlantMessage m)
    {
        var row = await db.Plants.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.Code)
            ?? Add(db.Plants, new Plant { Id = Guid.NewGuid(), CompanyId = companyId, ExternalCode = m.Code, Name = m.Name });

        row.Name = m.Name;
        row.Address = m.Address;
        row.City = m.City;
        row.Postcode = m.Postcode;
        row.Country = m.Country;
        row.Phone = m.Phone;
        row.Latitude = m.Latitude;
        row.Longitude = m.Longitude;
        Stamp(row, m.IsActive, m.Extra);

        await db.SaveChangesAsync();
        return row;
    }

    public async Task<ForwardingAgent> SaveForwardingAgentAsync(Guid companyId, ForwardingAgentMessage m)
    {
        var row = await db.ForwardingAgents.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.Code)
            ?? Add(db.ForwardingAgents, new ForwardingAgent { Id = Guid.NewGuid(), CompanyId = companyId, ExternalCode = m.Code, Name = m.Name });

        row.Name = m.Name;
        row.Address = m.Address;
        row.City = m.City;
        row.Postcode = m.Postcode;
        row.Country = m.Country;
        row.Phone = m.Phone;
        row.Email = m.Email;
        row.TaxId = m.TaxId;
        Stamp(row, m.IsActive, m.Extra);

        await db.SaveChangesAsync();
        return row;
    }

    public async Task<Vehicle> SaveVehicleAsync(Guid companyId, VehicleMessage m)
    {
        // The forwarding agent is optional, but if named it must exist
        Guid? agentId = null;
        if (!string.IsNullOrEmpty(m.ForwardingAgentCode))
        {
            agentId = (await db.ForwardingAgents.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.ForwardingAgentCode)
                ?? throw new MasterDataException($"Vehicle {m.Code}: unknown forwarding agent {m.ForwardingAgentCode}.")).Id;
        }

        var row = await db.Vehicles.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.Code)
            ?? Add(db.Vehicles, new Vehicle { Id = Guid.NewGuid(), CompanyId = companyId, ExternalCode = m.Code, Plate = m.Plate, Model = m.Model });

        row.Plate = m.Plate;
        row.Kind = m.Kind;
        row.Model = m.Model;
        row.Description = m.Description;
        row.ForwardingAgentId = agentId;
        Stamp(row, m.IsActive, m.Extra);

        await db.SaveChangesAsync();
        return row;
    }

    /// <summary>
    /// Creates or re-plans a delivery. A new delivery starts as Assigned. On an
    /// existing one the status is left alone — the app moves it forward —
    /// except a cancellation. A delivery already Delivered cannot be cancelled.
    /// </summary>
    public async Task<Delivery> SaveDeliveryAsync(Guid companyId, DeliveryMessage m)
    {
        var plant = await db.Plants.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.PlantCode)
            ?? throw new MasterDataException($"Delivery {m.PlantCode}/{m.Number}: unknown plant {m.PlantCode}.");
        var customer = await db.Customers.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.CustomerCode)
            ?? throw new MasterDataException($"Delivery {m.PlantCode}/{m.Number}: unknown customer {m.CustomerCode}.");
        var shipTo = await db.ShipTos.FirstOrDefaultAsync(x => x.CompanyId == companyId && x.ExternalCode == m.ShipToCode)
            ?? throw new MasterDataException($"Delivery {m.PlantCode}/{m.Number}: unknown ship-to {m.ShipToCode}.");
        if (shipTo.CustomerId != customer.Id)
            throw new MasterDataException($"Delivery {m.PlantCode}/{m.Number}: ship-to {m.ShipToCode} does not belong to customer {m.CustomerCode}.");

        var row = await db.Deliveries.FirstOrDefaultAsync(x => x.PlantId == plant.Id && x.Number == m.Number)
            ?? Add(db.Deliveries, new Delivery
            {
                Id = Guid.NewGuid(), CompanyId = companyId, PlantId = plant.Id, Number = m.Number,
                OrderNumber = m.OrderNumber, Material = m.Material, Status = DeliveryStatus.Assigned,
            });

        row.OrderNumber = m.OrderNumber;
        row.CustomerId = customer.Id;
        row.ShipToId = shipTo.Id;
        row.TruckPlate = m.TruckPlate;
        row.TrailerPlate = m.TrailerPlate;
        row.Material = m.Material;
        row.OrderedTons = m.OrderedTons;
        row.ScheduledAt = m.ScheduledAt;
        row.WindowStart = m.WindowStart;
        row.WindowEnd = m.WindowEnd;
        row.DistanceKm = m.DistanceKm;
        row.Notes = m.Notes;
        row.Extra = m.Extra ?? [];
        if (m.IsCancelled && row.Status != DeliveryStatus.Delivered)
            row.Status = DeliveryStatus.Cancelled;

        // Tell the app something changed (it asks "what changed since...")
        row.LastReceivedAt = Now;
        row.UpdatedAt = Now;

        await db.SaveChangesAsync();
        return row;
    }

    /// <summary>
    /// Records a weighbridge reading. A re-weigh adds a new row; the latest
    /// reading of each kind counts. Moving the status (1st weight → Loading,
    /// 2nd → In transit) comes with the weighbridge work in a later step.
    /// </summary>
    public async Task<Weighing> SaveWeighingAsync(Guid companyId, WeighingMessage m)
    {
        var delivery = await db.Deliveries
            .FirstOrDefaultAsync(x => x.CompanyId == companyId && x.Plant.ExternalCode == m.PlantCode && x.Number == m.Number)
            ?? throw new MasterDataException($"Weighing: unknown delivery {m.PlantCode}/{m.Number}.");

        var row = Add(db.Weighings, new Weighing
        {
            Id = Guid.NewGuid(), DeliveryId = delivery.Id, Kind = m.Kind, Tons = m.Tons,
            WeighedAt = m.WeighedAt, TicketNumber = m.TicketNumber, Weighbridge = m.Weighbridge,
        });
        delivery.UpdatedAt = Now;

        await db.SaveChangesAsync();
        return row;
    }

    private static T Add<T>(DbSet<T> set, T row) where T : class
    {
        set.Add(row);
        return row;
    }

    // The fields every master-data record shares
    private void Stamp(MasterData row, bool isActive, Dictionary<string, string>? extra)
    {
        row.IsActive = isActive;
        row.Extra = extra ?? [];
        row.LastReceivedAt = Now;
    }
}
