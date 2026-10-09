namespace TruckGo.BackOffice.Components.Shared;

/// <summary>How values are written on screen, the same way on every page.</summary>
public static class Show
{
    // Times are stored in UTC. Shown in the server's time zone for now; the
    // viewer's own time zone comes with the delivery screens.

    /// <summary>"09/10/2026 22:37", or "never".</summary>
    public static string DateTime(DateTime? utc) =>
        utc is { } t ? t.ToLocalTime().ToString("dd/MM/yyyy HH:mm") : "never";

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
