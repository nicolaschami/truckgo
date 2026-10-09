using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.EntityFrameworkCore;
using MudBlazor.Services;
using TruckGo.Admin;
using TruckGo.BackOffice.Components;
using TruckGo.BackOffice.Security;
using TruckGo.Data;

// ============================================================================
// TruckGo back office — the web site the office uses (Blazor Server).
// Screens: docs/back-office-design.md. Runs at http://localhost:5100 in
// development, next to the API (5000) and on the same database.
// ============================================================================

var builder = WebApplication.CreateBuilder(args);

// DATABASE (PostgreSQL). A factory, not one long-lived context: a Blazor
// page can stay open for hours, so each action opens its own short context.
builder.Services.AddDbContextFactory<TruckGoDb>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("TruckGo")));

// TruckGo's own data management (TruckGo.Core/Admin)
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<UserAdmin>();
builder.Services.AddScoped<SettingsAdmin>();

// LOGIN: a cookie, kept for a working day and renewed while the user is active
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(o =>
    {
        o.LoginPath = "/login";
        o.AccessDeniedPath = "/access-denied";
        o.ExpireTimeSpan = TimeSpan.FromHours(10);
        o.SlidingExpiration = true;
        o.Cookie.Name = "TruckGo.BackOffice";
    });
builder.Services.AddAuthorization(Policies.Configure);
builder.Services.AddCascadingAuthenticationState();

// SCREENS: Blazor components + the MudBlazor library (tables, dialogs...)
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();
builder.Services.AddMudServices();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);

app.UseAuthentication();
app.UseAuthorization();
app.UseAntiforgery();

// Styles, scripts and fonts are public: the login page needs them before
// anyone is signed in (the "signed in" rule covers pages, not these files)
app.MapStaticAssets().AllowAnonymous();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

// Log out: forget the cookie and go back to the login page
app.MapPost("/account/logout", async (HttpContext http) =>
{
    await http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
    return Results.LocalRedirect("/login");
}).AllowAnonymous(); // also for a user who still has a temporary password

// Development: create/upgrade the database and load the demo data
if (app.Environment.IsDevelopment() && app.Configuration.GetValue<bool>("Database:MigrateAndSeed"))
{
    await DevDatabase.MigrateAndSeedAsync(app.Services);
}

app.Run();
