using TruckGo.Data;

namespace TruckGo.Integration;

// ============================================================================
// The messages the other system sends to TruckGo — our neutral contract.
//
// Whatever transport is chosen later (an SQS queue, an API, ...), it only has
// to turn what it receives into one of these records and hand it to
// MasterDataImport. For now the seed data (Data/SeedData.cs) creates them.
//
// Records refer to each other by EXTERNAL CODE (the codes of the other
// system), never by TruckGo ids: a ship-to names its customer's code, a
// delivery names its plant, customer and ship-to codes.
//
// "Extra" carries client-specific named values (see MasterData.Extra).
// ============================================================================

/// <summary>A customer (sold-to) created or changed in the other system.</summary>
public record CustomerMessage(
    string Code,
    string Name,
    string? Address = null,
    string? City = null,
    string? Postcode = null,
    string? Country = null,
    string? Phone = null,
    string? TaxId = null,
    bool IsActive = true,
    Dictionary<string, string>? Extra = null);

/// <summary>A ship-to (delivery place) of a customer. Always with its location.</summary>
public record ShipToMessage(
    string Code,
    string CustomerCode,
    string Name,
    double Latitude,
    double Longitude,
    string? Address = null,
    string? City = null,
    string? Postcode = null,
    string? Country = null,
    string? ContactName = null,
    string? ContactPhone = null,
    string? DeliveryInstructions = null,
    string? OpeningHours = null,
    bool IsActive = true,
    Dictionary<string, string>? Extra = null);

/// <summary>A plant where trucks load.</summary>
public record PlantMessage(
    string Code,
    string Name,
    double Latitude,
    double Longitude,
    string? Address = null,
    string? City = null,
    string? Postcode = null,
    string? Country = null,
    string? Phone = null,
    bool IsActive = true,
    Dictionary<string, string>? Extra = null);

/// <summary>A forwarding agent (haulier).</summary>
public record ForwardingAgentMessage(
    string Code,
    string Name,
    string? Address = null,
    string? City = null,
    string? Postcode = null,
    string? Country = null,
    string? Phone = null,
    string? Email = null,
    string? TaxId = null,
    bool IsActive = true,
    Dictionary<string, string>? Extra = null);

/// <summary>A truck or trailer. The forwarding agent is optional.</summary>
public record VehicleMessage(
    string Code,
    string Plate,
    VehicleKind Kind,
    string Model,
    string? Description = null,
    string? ForwardingAgentCode = null,
    bool IsActive = true,
    Dictionary<string, string>? Extra = null);

/// <summary>
/// A delivery planned or changed in the other system: what, from which
/// plant, to which ship-to, with which truck and trailer, when.
/// <paramref name="IsCancelled"/> = true cancels it.
/// </summary>
public record DeliveryMessage(
    string PlantCode,
    string Number,
    string OrderNumber,
    string CustomerCode,
    string ShipToCode,
    string Material,
    double OrderedTons,
    DateTime ScheduledAt,
    DateTime WindowStart,
    DateTime WindowEnd,
    string? TruckPlate = null,
    string? TrailerPlate = null,
    double DistanceKm = 0,
    string? Notes = null,
    bool IsCancelled = false,
    Dictionary<string, string>? Extra = null);

/// <summary>A weighbridge reading for a delivery (1st = tare, 2nd = gross), in tonnes.</summary>
public record WeighingMessage(
    string PlantCode,
    string Number,
    WeighingKind Kind,
    double Tons,
    DateTime WeighedAt,
    string? TicketNumber = null,
    string? Weighbridge = null);

/// <summary>
/// A message that cannot be saved, e.g. a ship-to whose customer we never
/// received. The message says what is wrong so it can be fixed and resent.
/// </summary>
public class MasterDataException(string message) : Exception(message);
