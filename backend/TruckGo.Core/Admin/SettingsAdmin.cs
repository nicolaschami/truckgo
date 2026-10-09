using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Admin;

/// <summary>
/// The Settings screen (docs/back-office-design.md, section 3): one row of
/// settings per company, edited by its Admin. A company that never saved its
/// settings gets the defaults written in CompanySettings.
/// </summary>
public class SettingsAdmin(IDbContextFactory<TruckGoDb> dbFactory)
{
    // Allowed ranges: wide enough for any client, narrow enough to catch a typo
    // (e.g. 2000 instead of 200 m would make every truck "at the plant").
    public const double MinRadiusM = 20, MaxRadiusM = 2000;
    public const int MinSendIntervalSeconds = 10, MaxSendIntervalSeconds = 600;
    public const int MaxWarningMinutes = 24 * 60;
    public const int MinRetentionMonths = 1, MaxRetentionMonths = 120;

    /// <summary>The company's settings (defaults if never saved).</summary>
    public async Task<CompanySettings> GetAsync(Guid companyId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.CompanyId == companyId)
            ?? new CompanySettings { CompanyId = companyId };
    }

    /// <summary>Checks every value, then saves (creates the row the first time).</summary>
    public async Task SaveAsync(Guid companyId, CompanySettings values)
    {
        Check(values.GeofenceRadiusM, MinRadiusM, MaxRadiusM, "The geofence radius");
        Check(values.PositionSendIntervalSeconds, MinSendIntervalSeconds, MaxSendIntervalSeconds, "The position send interval");
        Check(values.LongWaitAtPlantMinutes, 1, MaxWarningMinutes, "Long wait at the plant");
        Check(values.LongWaitAtShipToMinutes, 1, MaxWarningMinutes, "Long wait at the ship-to");
        Check(values.WindowToleranceMinutes, 0, MaxWarningMinutes, "The delivery window tolerance");
        Check(values.LongStopMinutes, 1, MaxWarningMinutes, "Long unexpected stop");
        Check(values.GpsRetentionMonths, MinRetentionMonths, MaxRetentionMonths, "GPS retention");

        await using var db = await dbFactory.CreateDbContextAsync();
        var row = await db.Settings.FirstOrDefaultAsync(s => s.CompanyId == companyId);
        if (row is null)
        {
            row = new CompanySettings { CompanyId = companyId };
            db.Settings.Add(row);
        }

        row.GeofenceRadiusM = values.GeofenceRadiusM;
        row.PositionSendIntervalSeconds = values.PositionSendIntervalSeconds;
        row.LongWaitAtPlantMinutes = values.LongWaitAtPlantMinutes;
        row.LongWaitAtShipToMinutes = values.LongWaitAtShipToMinutes;
        row.WindowToleranceMinutes = values.WindowToleranceMinutes;
        row.LongStopMinutes = values.LongStopMinutes;
        row.GpsRetentionMonths = values.GpsRetentionMonths;
        await db.SaveChangesAsync();
    }

    private static void Check(double value, double min, double max, string what)
    {
        if (value < min || value > max)
            throw new AdminException($"{what} must be between {min} and {max}.");
    }
}
