using System.Security.Cryptography;

namespace TruckGo.Admin;

/// <summary>
/// Generates the secrets TruckGo hands out: temporary passwords for
/// back-office users and PINs for drivers. Both are shown ONCE on screen,
/// stored only as a hash, and must be changed at the next login.
/// </summary>
public static class Secrets
{
    // No look-alike characters (0/O, 1/l/I) so a password read aloud or
    // copied from the screen is typed right the first time
    private const string PasswordChars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";

    /// <summary>A random 10-character temporary password, e.g. "kR7mPq2xTb".</summary>
    public static string TemporaryPassword() =>
        RandomNumberGenerator.GetString(PasswordChars, 10);

    /// <summary>A random 4-digit driver PIN, e.g. "4071" (never 0000-style repeats).</summary>
    public static string DriverPin()
    {
        while (true)
        {
            var pin = RandomNumberGenerator.GetString("0123456789", 4);
            if (pin.Distinct().Count() > 1) return pin;
        }
    }
}

/// <summary>Login rules shared by drivers (app) and back-office users (web).</summary>
public static class LoginRules
{
    /// <summary>This many wrong PINs / passwords in a row lock the account...</summary>
    public const int MaxFailedLogins = 5;

    /// <summary>...for this long (or until an Admin unlocks it).</summary>
    public static readonly TimeSpan LockTime = TimeSpan.FromMinutes(5);

    /// <summary>Minimum length of a password chosen by a back-office user.</summary>
    public const int MinPasswordLength = 8;
}

/// <summary>
/// A request the back office refuses, with a message meant for the user
/// (e.g. "This email is already used"). Pages show it as it is.
/// </summary>
public class AdminException(string message) : Exception(message);
