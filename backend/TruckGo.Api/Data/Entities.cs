namespace TruckGo.Api.Data;

// ============================================================================
// TruckGo's own, vendor-neutral data model.
// Design: docs/back-office-design.md (section 5) and docs/backend-plan.md.
//
// Two kinds of data live here:
//
//  * MASTER DATA — customers, ship-tos, plants, forwarding agents, vehicles,
//    deliveries and weighings. They always come from the client's other
//    system (dispatching / ERP). TruckGo never creates or edits them by hand:
//    they enter only through the "save" step in Integration/MasterDataImport.cs.
//
//  * TRUCKGO'S OWN DATA — companies, drivers, back-office users, settings,
//    and (later) what the app records: status events, GPS positions, proof of
//    delivery. These are created and managed in TruckGo.
//
// Every row belongs to a Company: several clients can share one server and
// never see each other's data. All DateTime values are UTC.
// ============================================================================

/// <summary>
/// A client company using TruckGo (one per connection to an other system).
/// Everything else hangs below a company.
/// </summary>
public class Company
{
    public Guid Id { get; set; }

    /// <summary>Short unique code, e.g. "DEMO". Shown to the driver after login.</summary>
    public required string Code { get; set; }
    public required string Name { get; set; }
}

// ----------------------------------------------------------------------------
// MASTER DATA (received from the other system, view only in TruckGo)
// ----------------------------------------------------------------------------

/// <summary>
/// Fields shared by every master-data record. Not a table of its own: each
/// table that inherits it simply gets these columns.
/// </summary>
public abstract class MasterData
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }

    /// <summary>
    /// The record's code in the other system (customer number, plant code...).
    /// The save step looks a record up by this code: same code = update,
    /// new code = create. Unique per company.
    /// </summary>
    public required string ExternalCode { get; set; }

    /// <summary>
    /// False when the other system deactivates the record. We never delete
    /// master data: old deliveries still point to it.
    /// </summary>
    public bool IsActive { get; set; } = true;

    /// <summary>When the integration last sent this record — helps spot stale data.</summary>
    public DateTime LastReceivedAt { get; set; }

    /// <summary>
    /// "Extra info": client-specific named values we did not foresee (e.g.
    /// "Gate code" = "4512"). Stored as JSON; the screens show them as they
    /// are. When a value turns out to matter for every client, it becomes a
    /// real column instead.
    /// </summary>
    public Dictionary<string, string> Extra { get; set; } = [];
}

/// <summary>The customer who buys the goods (the "sold-to"). It has one or more ship-tos.</summary>
public class Customer : MasterData
{
    public required string Name { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Postcode { get; set; }
    public string? Country { get; set; }
    public string? Phone { get; set; }

    /// <summary>VAT / tax identification number.</summary>
    public string? TaxId { get; set; }

    public List<ShipTo> ShipTos { get; set; } = [];
}

/// <summary>
/// A place where a customer receives deliveries (a building site, a yard...).
/// It always comes with its GPS location: the app draws the site geofence
/// around it to remind the driver to press "I have arrived".
/// </summary>
public class ShipTo : MasterData
{
    public Guid CustomerId { get; set; }
    public Customer Customer { get; set; } = null!;

    public required string Name { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Postcode { get; set; }
    public string? Country { get; set; }

    // Location of the site. The geofence radius is NOT here: it is one
    // TruckGo setting for all plants and ship-tos (CompanySettings).
    public double Latitude { get; set; }
    public double Longitude { get; set; }

    /// <summary>Person to call on site (shown to the driver).</summary>
    public string? ContactName { get; set; }
    public string? ContactPhone { get; set; }

    /// <summary>Standing instructions for every delivery, e.g. "Gate 3, call before arriving".</summary>
    public string? DeliveryInstructions { get; set; }

    /// <summary>Free text as received, e.g. "Mon-Fri 07:00-17:00".</summary>
    public string? OpeningHours { get; set; }
}

/// <summary>
/// A plant (quarry, concrete or asphalt plant) where trucks load. Entering
/// its geofence moves the delivery to "At plant" automatically.
/// </summary>
public class Plant : MasterData
{
    // The plant's ExternalCode (e.g. "QN2") is also half of every delivery's
    // key: plant code + delivery number.
    public required string Name { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Postcode { get; set; }
    public string? Country { get; set; }
    public string? Phone { get; set; }

    public double Latitude { get; set; }
    public double Longitude { get; set; }
}

/// <summary>A transport company (haulier) that owns trucks and trailers.</summary>
public class ForwardingAgent : MasterData
{
    public required string Name { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Postcode { get; set; }
    public string? Country { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? TaxId { get; set; }
}

public enum VehicleKind { Truck, Trailer }

/// <summary>
/// A truck or a trailer. Its state (idle / at plant / on the road / at
/// ship-to) is NOT stored: TruckGo calculates it from the deliveries.
/// No max load either — capacity belongs to the dispatching system.
/// </summary>
public class Vehicle : MasterData
{
    /// <summary>Licence plate, unique per company. Deliveries refer to vehicles by plate.</summary>
    public required string Plate { get; set; }
    public VehicleKind Kind { get; set; }

    /// <summary>Optional: the haulier that owns it.</summary>
    public Guid? ForwardingAgentId { get; set; }
    public ForwardingAgent? ForwardingAgent { get; set; }

    /// <summary>Make and model, e.g. "Volvo FH16".</summary>
    public required string Model { get; set; }

    /// <summary>Short description, e.g. "Tractor unit 6x4" or "27 t payload".</summary>
    public string? Description { get; set; }
}

/// <summary>
/// Same statuses, same order, as the app (system-design.md). A delivery only
/// moves forward; Delivered and Cancelled are final.
/// </summary>
public enum DeliveryStatus
{
    Assigned,       // received from dispatching, assigned to a truck
    AtPlant,        // truck entered the plant geofence
    Loading,        // 1st weight (tare) received
    InTransit,      // 2nd weight (gross) received
    ArrivedAtSite,  // driver pressed "I have arrived"
    Unloading,      // driver started unloading
    Delivered,      // customer signed — final
    Cancelled,      // cancelled by the dispatching system — final
}

/// <summary>
/// One delivery: a load of material from a plant to a customer's ship-to,
/// assigned to a truck. Planned by the other system; its progress (status)
/// comes from the TruckGo app.
/// </summary>
public class Delivery
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }

    // The key in the whole system: plant + delivery number
    public Guid PlantId { get; set; }
    public Plant Plant { get; set; } = null!;
    public required string Number { get; set; }

    /// <summary>The sales order the delivery belongs to (for reference only).</summary>
    public required string OrderNumber { get; set; }

    // Who receives it. The delivery points to the master records instead of
    // copying them, so a corrected ship-to location also fixes open deliveries.
    public Guid CustomerId { get; set; }
    public Customer Customer { get; set; } = null!;
    public Guid ShipToId { get; set; }
    public ShipTo ShipTo { get; set; } = null!;

    // Vehicles as assigned by the dispatching system. Plates, not links:
    // the delivery keeps the plates it was delivered with even if a vehicle
    // is renamed or removed later.
    public string? TruckPlate { get; set; }
    public string? TrailerPlate { get; set; }

    public required string Material { get; set; }

    /// <summary>Always tonnes (TNE).</summary>
    public double OrderedTons { get; set; }

    /// <summary>Planned arrival time at the ship-to.</summary>
    public DateTime ScheduledAt { get; set; }

    // Delivery window agreed with the customer
    public DateTime WindowStart { get; set; }
    public DateTime WindowEnd { get; set; }

    /// <summary>Planned road distance plant → ship-to.</summary>
    public double DistanceKm { get; set; }

    /// <summary>Notes for this delivery only (standing site notes are on the ship-to).</summary>
    public string? Notes { get; set; }

    public DeliveryStatus Status { get; set; }

    /// <summary>
    /// Any change (status, weight, re-planning...) updates this time. The app
    /// asks "what changed since my last call?" with it.
    /// </summary>
    public DateTime UpdatedAt { get; set; }

    /// <summary>When the integration last sent this delivery.</summary>
    public DateTime LastReceivedAt { get; set; }

    /// <summary>Client-specific extra info (see MasterData.Extra).</summary>
    public Dictionary<string, string> Extra { get; set; } = [];

    public List<Weighing> Weighings { get; set; } = [];
}

public enum WeighingKind { First, Second }

/// <summary>
/// A weighbridge reading, sent by the other system. Kept as history: a
/// re-weigh adds a row, the latest of each kind counts.
/// First = tare (empty truck), second = gross (loaded); net = gross - tare.
/// </summary>
public class Weighing
{
    public Guid Id { get; set; }
    public Guid DeliveryId { get; set; }
    public WeighingKind Kind { get; set; }

    /// <summary>Always tonnes (TNE).</summary>
    public double Tons { get; set; }
    public DateTime WeighedAt { get; set; }
    public string? TicketNumber { get; set; }

    /// <summary>Which weighbridge, e.g. "WB-1".</summary>
    public string? Weighbridge { get; set; }
}

// ----------------------------------------------------------------------------
// TRUCKGO'S OWN DATA (created and managed in TruckGo)
// ----------------------------------------------------------------------------

/// <summary>
/// A driver's login for the app. Owned by TruckGo even when the same person
/// exists in the other system. Never deleted — only deactivated — so
/// deliveries and traces keep the driver's name.
/// </summary>
public class Driver
{
    public Guid Id { get; set; }
    public Guid CompanyId { get; set; }
    public Company Company { get; set; } = null!;

    /// <summary>Alphanumeric, unique on the whole server. Never changes once created.</summary>
    public required string Username { get; set; }

    /// <summary>
    /// The 4-digit PIN, hashed (never stored in clear). TruckGo generates it,
    /// shows it once in the back office, and the driver must change it.
    /// </summary>
    public required string PinHash { get; set; }

    /// <summary>True after creation or a PIN reset: the app asks for a new PIN at login.</summary>
    public bool MustChangePin { get; set; }

    public required string DisplayName { get; set; }
    public string? Phone { get; set; }
    public bool IsActive { get; set; } = true;

    // Too many wrong PINs lock the account for a while
    public int FailedLogins { get; set; }
    public DateTime? LockedUntil { get; set; }

    // Shown in the back office's driver screen
    public DateTime? LastLoginAt { get; set; }
    public string? LastDeviceId { get; set; }
}

/// <summary>What a back-office user may do (docs/back-office-design.md, screen 5).</summary>
public enum UserRole
{
    /// <summary>TruckGo staff: creates client companies and their first Admin. Belongs to no company.</summary>
    SuperAdmin,

    /// <summary>Everything inside one company: users, drivers, settings, all screens.</summary>
    Admin,

    /// <summary>All screens; manages drivers; may move a delivery status forward with a reason.</summary>
    Dispatcher,

    /// <summary>All screens, changes nothing.</summary>
    Viewer,
}

/// <summary>
/// A person who logs in to the back office (web) with email + password.
/// Never deleted — only deactivated — so the history keeps who did what.
/// </summary>
public class BackOfficeUser
{
    public Guid Id { get; set; }

    /// <summary>The user's company; null only for a SuperAdmin.</summary>
    public Guid? CompanyId { get; set; }
    public Company? Company { get; set; }

    /// <summary>Login name, unique on the whole server. Stored lower-case.</summary>
    public required string Email { get; set; }

    /// <summary>Hashed. TruckGo generates a temporary password, shown once.</summary>
    public required string PasswordHash { get; set; }

    /// <summary>True after creation or a reset: the user must choose a new password at login.</summary>
    public bool MustChangePassword { get; set; }

    public required string DisplayName { get; set; }
    public UserRole Role { get; set; }
    public bool IsActive { get; set; } = true;

    // Same lock rule as the drivers
    public int FailedLogins { get; set; }
    public DateTime? LockedUntil { get; set; }
    public DateTime? LastLoginAt { get; set; }
}

/// <summary>
/// TruckGo settings, one row per company, edited by its Admin
/// (docs/back-office-design.md, section 3). The defaults below are used
/// until someone changes them.
/// </summary>
public class CompanySettings
{
    /// <summary>The company these settings belong to (also the row's key).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>One geofence radius for every plant and ship-to, in metres.</summary>
    public double GeofenceRadiusM { get; set; } = 200;

    /// <summary>How often the app sends its GPS positions to the server, in seconds.</summary>
    public int PositionSendIntervalSeconds { get; set; } = 60;

    // Warning limits, in minutes
    /// <summary>Warn when a truck is at the plant / loading longer than this.</summary>
    public int LongWaitAtPlantMinutes { get; set; } = 30;

    /// <summary>Warn when a truck is at the ship-to / unloading longer than this.</summary>
    public int LongWaitAtShipToMinutes { get; set; } = 45;

    /// <summary>Warn when the truck arrives more than this outside the delivery window.</summary>
    public int WindowToleranceMinutes { get; set; } = 0;

    /// <summary>A stop outside plant and ship-to longer than this is shown on the trace and warned.</summary>
    public int LongStopMinutes { get; set; } = 15;

    /// <summary>GPS positions older than this are deleted every night. Deliveries are kept for good.</summary>
    public int GpsRetentionMonths { get; set; } = 12;
}
