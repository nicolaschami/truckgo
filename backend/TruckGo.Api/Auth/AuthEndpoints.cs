using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using TruckGo.Api.Data;

namespace TruckGo.Api.Auth;

public class JwtOptions
{
    public string Issuer { get; set; } = "truckgo";
    public string Audience { get; set; } = "truckgo-app";

    /// <summary>At least 32 characters. Never commit a production key.</summary>
    public string SigningKey { get; set; } = "";
    public int AccessTokenMinutes { get; set; } = 60;

    public SymmetricSecurityKey Key() => new(Encoding.UTF8.GetBytes(SigningKey));
}

public record LoginRequest(string Username, string Pin, string? DeviceId);
public record DriverInfo(string Username, string DisplayName, string CompanyCode, string CompanyName);
public record LoginResponse(string AccessToken, DateTime ExpiresAt, DriverInfo Driver);

public static class AuthEndpoints
{
    public const int MaxFailedLogins = 5;
    public static readonly TimeSpan LockTime = TimeSpan.FromMinutes(5);

    public static void MapAuthEndpoints(this IEndpointRouteBuilder api)
    {
        api.MapPost("/auth/login", Login)
            .WithTags("Auth")
            .WithSummary("Log in with username and numeric PIN")
            .AllowAnonymous();
    }

    private static async Task<IResult> Login(
        LoginRequest request, TruckGoDb db, IOptions<JwtOptions> jwt, TimeProvider clock)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var driver = await db.Drivers.Include(d => d.Company)
            .FirstOrDefaultAsync(d => d.Username == request.Username.Trim());

        // Same answer for "unknown user" and "wrong PIN": don't reveal which
        if (driver is null || !driver.IsActive)
            return Unauthorized();

        if (driver.LockedUntil > now)
            return Results.Problem(
                statusCode: StatusCodes.Status423Locked,
                title: "Account locked",
                detail: "Too many wrong PINs. Try again in a few minutes.");

        var hasher = new PasswordHasher<Driver>();
        if (hasher.VerifyHashedPassword(driver, driver.PinHash, request.Pin) == PasswordVerificationResult.Failed)
        {
            driver.FailedLogins++;
            if (driver.FailedLogins >= MaxFailedLogins)
            {
                driver.LockedUntil = now + LockTime;
                driver.FailedLogins = 0;
            }
            await db.SaveChangesAsync();
            return Unauthorized();
        }

        driver.FailedLogins = 0;
        driver.LockedUntil = null;
        // Shown in the back office's driver screen ("last login", "device")
        driver.LastLoginAt = now;
        driver.LastDeviceId = request.DeviceId;
        await db.SaveChangesAsync();

        var expires = now.AddMinutes(jwt.Value.AccessTokenMinutes);
        var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = jwt.Value.Issuer,
            Audience = jwt.Value.Audience,
            Subject = new ClaimsIdentity(
            [
                new Claim(JwtRegisteredClaimNames.Sub, driver.Id.ToString()),
                new Claim(JwtRegisteredClaimNames.UniqueName, driver.Username),
                new Claim(CurrentDriver.CompanyClaim, driver.CompanyId.ToString()),
            ]),
            IssuedAt = now,
            NotBefore = now,
            Expires = expires,
            SigningCredentials = new SigningCredentials(jwt.Value.Key(), SecurityAlgorithms.HmacSha256),
        });

        return Results.Ok(new LoginResponse(
            token,
            expires,
            new DriverInfo(driver.Username, driver.DisplayName, driver.Company.Code, driver.Company.Name)));
    }

    private static IResult Unauthorized() => Results.Problem(
        statusCode: StatusCodes.Status401Unauthorized,
        title: "Login failed",
        detail: "Wrong username or PIN.");
}

/// <summary>Who is calling, from the login token.</summary>
public static class CurrentDriver
{
    public const string CompanyClaim = "company";

    public static Guid CompanyId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(CompanyClaim)!);
}
