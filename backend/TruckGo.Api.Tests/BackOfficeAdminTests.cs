using Microsoft.EntityFrameworkCore;
using TruckGo.Admin;
using TruckGo.Data;

namespace TruckGo.Api.Tests;

/// <summary>
/// Back-office users and settings (TruckGo.Core/Admin) — the logic behind
/// screen 5 of docs/back-office-design.md.
/// </summary>
public class BackOfficeAdminTests
{
    private const string AdminEmail = "admin@demo.truckgo.local";

    [Fact]
    public async Task The_demo_admin_logs_in_and_wrong_passwords_lock_the_account()
    {
        using var db = await TestDb.SeededAsync();
        var users = new UserAdmin(db, TimeProvider.System);

        var ok = await users.LoginAsync(" Admin@Demo.TruckGo.local ", SeedData.BackOfficePassword); // case and spaces ignored
        Assert.Equal(LoginResult.Ok, ok.Result);
        Assert.Equal("TruckGo Demo", ok.User!.Company!.Name);

        for (var i = 0; i < LoginRules.MaxFailedLogins; i++)
            Assert.Equal(LoginResult.Failed, (await users.LoginAsync(AdminEmail, "wrong")).Result);

        // Even the right password is refused while locked
        Assert.Equal(LoginResult.Locked, (await users.LoginAsync(AdminEmail, SeedData.BackOfficePassword)).Result);
    }

    [Fact]
    public async Task A_new_user_gets_a_temporary_password_and_must_change_it()
    {
        using var db = await TestDb.SeededAsync();
        var users = new UserAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();

        var temporary = await users.CreateAsync(company, "Maria@Example.com", "María López", UserRole.Dispatcher);
        Assert.Equal(10, temporary.Length);

        // Logging in with it works, but only to choose a new password
        var login = await users.LoginAsync("maria@example.com", temporary);
        Assert.Equal(LoginResult.MustChangePassword, login.Result);

        await users.ChangePasswordAsync(login.User!.Id, temporary, "my-own-secret");
        Assert.Equal(LoginResult.Ok, (await users.LoginAsync("maria@example.com", "my-own-secret")).Result);
        Assert.Equal(LoginResult.Failed, (await users.LoginAsync("maria@example.com", temporary)).Result);
    }

    [Fact]
    public async Task Refused_requests_explain_why()
    {
        using var db = await TestDb.SeededAsync();
        var users = new UserAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();
        var admin = (await users.ListAsync(company)).Single(u => u.Email == AdminEmail);

        await AssertRefused("already used", () => users.CreateAsync(company, AdminEmail, "Copy", UserRole.Viewer));
        await AssertRefused("cannot be given", () => users.CreateAsync(company, "x@y.com", "X", UserRole.SuperAdmin));
        await AssertRefused("your own role", () => users.UpdateAsync(company, admin.Id, admin.Id, "Me", UserRole.Viewer));
        await AssertRefused("deactivate yourself", () => users.SetActiveAsync(company, admin.Id, admin.Id, false));
        await AssertRefused("at least", () => users.ChangePasswordAsync(admin.Id, SeedData.BackOfficePassword, "short"));
        await AssertRefused("not correct", () => users.ChangePasswordAsync(admin.Id, "wrong-current", "long-enough-1"));
    }

    [Fact]
    public async Task Reset_unlocks_and_deactivated_users_cannot_log_in()
    {
        using var db = await TestDb.SeededAsync();
        var users = new UserAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();
        var admin = (await users.ListAsync(company)).Single(u => u.Email == AdminEmail);
        var viewer = (await users.ListAsync(company)).Single(u => u.Role == UserRole.Viewer);

        // The viewer forgets the password and gets locked out
        for (var i = 0; i < LoginRules.MaxFailedLogins; i++) await users.LoginAsync(viewer.Email, "wrong");
        Assert.True((await users.ListAsync(company)).Single(u => u.Id == viewer.Id).IsLocked);

        // The Admin resets it: unlocked, temporary password works
        var temporary = await users.ResetPasswordAsync(company, viewer.Id);
        Assert.False((await users.ListAsync(company)).Single(u => u.Id == viewer.Id).IsLocked);
        Assert.Equal(LoginResult.MustChangePassword, (await users.LoginAsync(viewer.Email, temporary)).Result);

        // Deactivated: refused, and still listed (never deleted)
        await users.SetActiveAsync(company, admin.Id, viewer.Id, false);
        Assert.Equal(LoginResult.Failed, (await users.LoginAsync(viewer.Email, temporary)).Result);
        Assert.False((await users.ListAsync(company)).Single(u => u.Id == viewer.Id).IsActive);
    }

    [Fact]
    public async Task An_admin_never_sees_or_changes_another_companys_users()
    {
        using var db = await TestDb.SeededAsync();
        var users = new UserAdmin(db, TimeProvider.System);
        var company = await db.DemoCompanyAsync();
        var otherCompany = Guid.NewGuid();
        await using (var ctx = db.CreateDbContext())
        {
            ctx.Companies.Add(new Company { Id = otherCompany, Code = "OTHER", Name = "Other Co" });
            await ctx.SaveChangesAsync();
        }
        await users.CreateAsync(otherCompany, "boss@other.com", "Other Boss", UserRole.Admin);
        var otherBoss = (await users.ListAsync(otherCompany)).Single();

        Assert.DoesNotContain(await users.ListAsync(company), u => u.Email == "boss@other.com");
        await AssertRefused("does not exist", () => users.ResetPasswordAsync(company, otherBoss.Id));
    }

    [Fact]
    public async Task Settings_start_with_the_defaults_and_refuse_values_out_of_range()
    {
        using var db = await TestDb.SeededAsync();
        var settings = new SettingsAdmin(db);
        var company = await db.DemoCompanyAsync();

        var values = await settings.GetAsync(company);
        Assert.Equal(200, values.GeofenceRadiusM);
        Assert.Equal(60, values.PositionSendIntervalSeconds);

        values.GeofenceRadiusM = 250;
        await settings.SaveAsync(company, values);
        Assert.Equal(250, (await settings.GetAsync(company)).GeofenceRadiusM);

        values.GeofenceRadiusM = 5000; // a typo: every truck would be "at the plant"
        await AssertRefused("geofence radius", () => settings.SaveAsync(company, values));
        Assert.Equal(250, (await settings.GetAsync(company)).GeofenceRadiusM);
    }

    private static async Task AssertRefused(string expected, Func<Task> action)
    {
        var e = await Assert.ThrowsAsync<AdminException>(action);
        Assert.Contains(expected, e.Message, StringComparison.OrdinalIgnoreCase);
    }
}
