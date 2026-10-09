using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using TruckGo.Data;

namespace TruckGo.BackOffice.Security;

/// <summary>
/// What the login cookie remembers about the user. Read on every page to
/// know who is working and in which company.
/// </summary>
public static class BackOfficeClaims
{
    public const string Company = "company";
    public const string CompanyName = "company_name";

    /// <summary>
    /// Present while the user still has a temporary password: they may only
    /// open the "choose a new password" page until they change it.
    /// </summary>
    public const string MustChangePassword = "must_change_password";

    /// <summary>Builds the signed-in user from the database row.</summary>
    public static ClaimsPrincipal Create(BackOfficeUser user, string? companyName)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.DisplayName),
            new(ClaimTypes.Email, user.Email),
            new(ClaimTypes.Role, user.Role.ToString()),
        };
        if (user.CompanyId is { } company)
        {
            claims.Add(new(Company, company.ToString()));
            claims.Add(new(CompanyName, companyName ?? ""));
        }
        if (user.MustChangePassword) claims.Add(new(MustChangePassword, "1"));

        return new ClaimsPrincipal(new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme));
    }

    public static Guid UserId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);

    /// <summary>The user's company; null for a TruckGo SuperAdmin.</summary>
    public static Guid? CompanyId(this ClaimsPrincipal user) =>
        user.FindFirstValue(Company) is { } id ? Guid.Parse(id) : null;

    public static bool MustChangePasswordFirst(this ClaimsPrincipal user) =>
        user.HasClaim(c => c.Type == MustChangePassword);
}

/// <summary>
/// Who may open what. Pages say which policy they need with
/// <c>@attribute [Authorize(Policy = ...)]</c>; the menu hides what the
/// user may not open.
/// </summary>
public static class Policies
{
    /// <summary>Users and Settings screens: Admin only.</summary>
    public const string Admin = "Admin";

    /// <summary>Managing drivers (later): Admin or Dispatcher.</summary>
    public const string ManageDrivers = "ManageDrivers";

    /// <summary>The "choose a new password" page: any signed-in user, even with a temporary password.</summary>
    public const string ChangePassword = "ChangePassword";

    public static void Configure(AuthorizationOptions options)
    {
        // Every page by default: signed in AND no temporary password pending
        var signedIn = new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .RequireAssertion(c => !c.User.MustChangePasswordFirst())
            .Build();
        options.DefaultPolicy = signedIn;
        options.FallbackPolicy = signedIn;

        options.AddPolicy(Admin, p => p.Combine(signedIn).RequireRole(nameof(UserRole.Admin)));
        options.AddPolicy(ManageDrivers, p => p.Combine(signedIn)
            .RequireRole(nameof(UserRole.Admin), nameof(UserRole.Dispatcher)));
        options.AddPolicy(ChangePassword, p => p.RequireAuthenticatedUser());
    }
}
