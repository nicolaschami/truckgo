using TruckGo.Data;

namespace TruckGo.BackOffice.Components.Shared;

/// <summary>How values are written on screen, the same way on every page.</summary>
public static class Show
{
    /// <summary>A delivery status in words, as the drivers see it in the app.</summary>
    public static string Status(DeliveryStatus status) => status switch
    {
        DeliveryStatus.Assigned => "Assigned",
        DeliveryStatus.AtPlant => "At plant",
        DeliveryStatus.Loading => "Loading",
        DeliveryStatus.InTransit => "In transit",
        DeliveryStatus.ArrivedAtSite => "Arrived at site",
        DeliveryStatus.Unloading => "Unloading",
        DeliveryStatus.Delivered => "Delivered",
        DeliveryStatus.Cancelled => "Cancelled",
        _ => status.ToString(),
    };

    /// <summary>
    /// The badge colour of a status (app.css): grey = not started, blue = at
    /// the plant, amber = on the road, purple = at the site, green = done.
    /// </summary>
    public static string StatusBadge(DeliveryStatus status) => status switch
    {
        DeliveryStatus.Assigned => "badge-gray",
        DeliveryStatus.AtPlant or DeliveryStatus.Loading => "badge-blue",
        DeliveryStatus.InTransit => "badge-amber",
        DeliveryStatus.ArrivedAtSite or DeliveryStatus.Unloading => "badge-purple",
        DeliveryStatus.Delivered => "badge-green",
        _ => "badge-red", // Cancelled
    };

    /// <summary>A vehicle's state in words (calculated from its delivery).</summary>
    public static string State(TruckGo.Queries.VehicleState state) => state switch
    {
        TruckGo.Queries.VehicleState.AtPlant => "At plant",
        TruckGo.Queries.VehicleState.OnTheRoad => "On the road",
        TruckGo.Queries.VehicleState.AtShipTo => "At ship-to",
        _ => "Idle",
    };

    /// <summary>The same colours as the delivery statuses: blue plant, amber road, purple site, grey idle.</summary>
    public static string StateBadge(TruckGo.Queries.VehicleState state) => state switch
    {
        TruckGo.Queries.VehicleState.AtPlant => "badge-blue",
        TruckGo.Queries.VehicleState.OnTheRoad => "badge-amber",
        TruckGo.Queries.VehicleState.AtShipTo => "badge-purple",
        _ => "badge-gray",
    };

    /// <summary>"12.50 t" — quantities are always tonnes.</summary>
    public static string Tonnes(double tons) => $"{tons:0.00} t";

    /// <summary>Address parts joined on one line, skipping the empty ones.</summary>
    public static string Line(params string?[] parts) =>
        string.Join(", ", parts.Where(p => !string.IsNullOrWhiteSpace(p)));

    // Times are stored in UTC. Shown in the server's time zone for now; the
    // viewer's own time zone comes with the delivery screens.

    /// <summary>"09/10/2026 22:37", or "never".</summary>
    public static string DateTime(DateTime? utc) =>
        utc is { } t ? t.ToLocalTime().ToString("dd/MM/yyyy HH:mm") : "never";

    /// <summary>"09:30" — a time of day, in the server's time zone (see above).</summary>
    public static string Time(DateTime utc) => utc.ToLocalTime().ToString("HH:mm");

    /// <summary>
    /// Today, as the UTC time range the queries need: from local midnight to
    /// the next local midnight (in the server's time zone for now).
    /// </summary>
    public static (DateTime FromUtc, DateTime ToUtc) Today()
    {
        var localMidnight = System.DateTime.Now.Date;
        return (localMidnight.ToUniversalTime(), localMidnight.AddDays(1).ToUniversalTime());
    }

    /// <summary>How long since a moment, as a waiting time: "4 min", "1 h 05".</summary>
    public static string Duration(DateTime sinceUtc)
    {
        var d = System.DateTime.UtcNow - sinceUtc;
        if (d < TimeSpan.Zero) d = TimeSpan.Zero;
        return d.TotalMinutes < 60 ? $"{(int)d.TotalMinutes} min" : $"{(int)d.TotalHours} h {d.Minutes:00}";
    }

    /// <summary>"just now", "12 min ago", "3 h ago", "yesterday", "5 days ago", then the date.</summary>
    public static string Ago(DateTime? utc)
    {
        if (utc is not { } t) return "never";
        var age = System.DateTime.UtcNow - t;
        return age.TotalMinutes switch
        {
            < 1 => "just now",
            < 60 => $"{(int)age.TotalMinutes} min ago",
            < 24 * 60 => $"{(int)age.TotalHours} h ago",
            < 48 * 60 => "yesterday",
            < 7 * 24 * 60 => $"{(int)age.TotalDays} days ago",
            _ => t.ToLocalTime().ToString("dd/MM/yyyy"),
        };
    }
}
