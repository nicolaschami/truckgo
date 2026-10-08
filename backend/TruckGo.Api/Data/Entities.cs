namespace TruckGo.Api.Data;

// TruckGo's own, vendor-neutral data model (see docs/backend-plan.md).
// Every row belongs to a Company: several customers can share one server.
// All DateTime values are UTC.

public class Company
{
    public Guid Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
}

public class Driver
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }
    public Company Company { get; set; } = null!;

    /// <summary>Alphanumeric, unique on the whole server.</summary>
    public required string Username { get; set; }
    public required string PinHash { get; set; }
    public required string DisplayName { get; set; }
    public bool IsActive { get; set; } = true;

    // Too many wrong PINs lock the account for a while
    public int FailedLogins { get; set; }
    public DateTime? LockedUntil { get; set; }
}

public enum VehicleStatus { Available, InUse, Maintenance }

public class Vehicle
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }
    public required string Plate { get; set; }
    public bool IsTruck { get; set; }
    public required string Model { get; set; }
    public required string Detail { get; set; }
    public VehicleStatus Status { get; set; }
}

public class Plant
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double GeofenceRadiusM { get; set; } = 200;
}

/// <summary>Same statuses, same order, as the app (system-design.md).</summary>
public enum DeliveryStatus
{
    Assigned,
    AtPlant,
    Loading,
    InTransit,
    ArrivedAtSite,
    Unloading,
    Delivered,
    Cancelled,
}

public class Delivery
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }

    // The key in the whole system: plant + delivery number
    public Guid PlantId { get; set; }
    public Plant Plant { get; set; } = null!;
    public required string Number { get; set; }

    public required string OrderNumber { get; set; }
    public string? TruckPlate { get; set; }

    public required string SoldToCode { get; set; }
    public required string SoldToName { get; set; }

    // Ship-to as planned for this delivery
    public required string ShipToName { get; set; }
    public required string ShipToAddress { get; set; }
    public double SiteLatitude { get; set; }
    public double SiteLongitude { get; set; }
    public double SiteGeofenceRadiusM { get; set; } = 200;
    public required string SiteContact { get; set; }
    public string? SitePhone { get; set; }

    public required string Material { get; set; }
    public double OrderedTons { get; set; }
    public DateTime ScheduledAt { get; set; }
    public DateTime WindowStart { get; set; }
    public DateTime WindowEnd { get; set; }
    public double DistanceKm { get; set; }
    public string? Notes { get; set; }

    public DeliveryStatus Status { get; set; }

    /// <summary>Any change (status, weight...) — drives the app's "since" sync.</summary>
    public DateTime UpdatedAt { get; set; }

    public List<Weighing> Weighings { get; set; } = [];
}

public enum WeighingKind { First, Second }

/// <summary>
/// A weighbridge reading. Kept as history: a re-weigh adds a row, the latest
/// of each kind counts. First = tare (empty truck), second = gross (loaded).
/// </summary>
public class Weighing
{
    public Guid Id { get; set; }
    public Guid DeliveryId { get; set; }
    public WeighingKind Kind { get; set; }
    public double Tons { get; set; }
    public DateTime WeighedAt { get; set; }
    public string? TicketNumber { get; set; }
    public string? Weighbridge { get; set; }
}
