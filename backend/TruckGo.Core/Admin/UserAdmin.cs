using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using TruckGo.Data;

namespace TruckGo.Admin;

/// <summary>One line of the Users screen.</summary>
public record UserRow(
    Guid Id,
    string Email,
    string DisplayName,
    UserRole Role,
    bool IsActive,
    bool IsLocked,
    bool MustChangePassword,
    DateTime? LastLoginAt);

public enum LoginResult
{
    /// <summary>Right password: go in.</summary>
    Ok,
    /// <summary>Right password, but it is a temporary one: choose a new password first.</summary>
    MustChangePassword,
    /// <summary>Unknown email, inactive user or wrong password (same answer: reveals nothing).</summary>
    Failed,
    /// <summary>Too many wrong passwords: wait, or ask an Admin to unlock.</summary>
    Locked,
}

public record LoginOutcome(LoginResult Result, BackOfficeUser? User = null);

/// <summary>
/// Back-office users (docs/back-office-design.md, screen 5): login, and what
/// an Admin can do on the Users screen. Users are TruckGo's own data.
///
/// Every method works inside ONE company (the Admin's), so an Admin can never
/// see or change another company's users. Each call opens its own short
/// database context — the right pattern for Blazor Server, where a page can
/// stay open for hours.
/// </summary>
public class UserAdmin(IDbContextFactory<TruckGoDb> dbFactory, TimeProvider clock)
{
    private readonly PasswordHasher<BackOfficeUser> _hasher = new();
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    // ------------------------------------------------------------------
    // Login and own password
    // ------------------------------------------------------------------

    /// <summary>Checks email + password, with the same lock rule as the drivers.</summary>
    public async Task<LoginOutcome> LoginAsync(string email, string password)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var user = await db.Users.Include(u => u.Company).FirstOrDefaultAsync(u => u.Email == Normalize(email));
        if (user is null || !user.IsActive) return new(LoginResult.Failed);
        if (user.LockedUntil > Now) return new(LoginResult.Locked);

        if (_hasher.VerifyHashedPassword(user, user.PasswordHash, password) == PasswordVerificationResult.Failed)
        {
            user.FailedLogins++;
            if (user.FailedLogins >= LoginRules.MaxFailedLogins)
            {
                user.LockedUntil = Now + LoginRules.LockTime;
                user.FailedLogins = 0;
            }
            await db.SaveChangesAsync();
            return new(LoginResult.Failed);
        }

        user.FailedLogins = 0;
        user.LockedUntil = null;
        user.LastLoginAt = Now;
        await db.SaveChangesAsync();
        return new(user.MustChangePassword ? LoginResult.MustChangePassword : LoginResult.Ok, user);
    }

    /// <summary>
    /// The user chooses a new password (forced after a temporary one).
    /// Needs the current password, so a forgotten open browser is not enough.
    /// </summary>
    public async Task<BackOfficeUser> ChangePasswordAsync(Guid userId, string currentPassword, string newPassword)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var user = await db.Users.Include(u => u.Company).SingleAsync(u => u.Id == userId);

        if (_hasher.VerifyHashedPassword(user, user.PasswordHash, currentPassword) == PasswordVerificationResult.Failed)
            throw new AdminException("The current password is not correct.");
        if (newPassword.Length < LoginRules.MinPasswordLength)
            throw new AdminException($"The new password needs at least {LoginRules.MinPasswordLength} characters.");
        if (newPassword == currentPassword)
            throw new AdminException("The new password must be different from the current one.");

        user.PasswordHash = _hasher.HashPassword(user, newPassword);
        user.MustChangePassword = false;
        await db.SaveChangesAsync();
        return user;
    }

    // ------------------------------------------------------------------
    // The Users screen (Admin only)
    // ------------------------------------------------------------------

    /// <summary>All users of the company, active first, then by name.</summary>
    public async Task<List<UserRow>> ListAsync(Guid companyId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var now = Now;
        return await db.Users
            .Where(u => u.CompanyId == companyId)
            .OrderByDescending(u => u.IsActive).ThenBy(u => u.DisplayName)
            .Select(u => new UserRow(u.Id, u.Email, u.DisplayName, u.Role, u.IsActive,
                u.LockedUntil != null && u.LockedUntil > now, u.MustChangePassword, u.LastLoginAt))
            .ToListAsync();
    }

    /// <summary>
    /// Creates a user with a generated temporary password. Returns the
    /// password so the screen can show it ONCE; it is never shown again.
    /// </summary>
    public async Task<string> CreateAsync(Guid companyId, string email, string displayName, UserRole role)
    {
        CheckRole(role);
        email = Normalize(email);
        if (!email.Contains('@') || email.Length < 5) throw new AdminException("Please enter a valid email.");
        if (string.IsNullOrWhiteSpace(displayName)) throw new AdminException("Please enter the user's name.");

        await using var db = await dbFactory.CreateDbContextAsync();
        // Unique on the whole server: the login screen does not ask for a company
        if (await db.Users.AnyAsync(u => u.Email == email))
            throw new AdminException("This email is already used.");

        var password = Secrets.TemporaryPassword();
        var user = new BackOfficeUser
        {
            Id = Guid.NewGuid(), CompanyId = companyId, Email = email, PasswordHash = "",
            DisplayName = displayName.Trim(), Role = role, MustChangePassword = true,
        };
        user.PasswordHash = _hasher.HashPassword(user, password);
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return password;
    }

    /// <summary>Changes name and role. The email (login) never changes. You cannot change your own role.</summary>
    public async Task UpdateAsync(Guid companyId, Guid actingUserId, Guid userId, string displayName, UserRole role)
    {
        CheckRole(role);
        if (string.IsNullOrWhiteSpace(displayName)) throw new AdminException("Please enter the user's name.");

        await using var db = await dbFactory.CreateDbContextAsync();
        var user = await FindAsync(db, companyId, userId);
        // Stops an Admin from removing their own rights by mistake
        if (userId == actingUserId && role != user.Role)
            throw new AdminException("You cannot change your own role.");

        user.DisplayName = displayName.Trim();
        user.Role = role;
        await db.SaveChangesAsync();
    }

    /// <summary>
    /// Gives the user a new temporary password (they forgot theirs). Also
    /// unlocks the account. Returns the password to show ONCE.
    /// </summary>
    public async Task<string> ResetPasswordAsync(Guid companyId, Guid userId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var user = await FindAsync(db, companyId, userId);

        var password = Secrets.TemporaryPassword();
        user.PasswordHash = _hasher.HashPassword(user, password);
        user.MustChangePassword = true;
        user.FailedLogins = 0;
        user.LockedUntil = null;
        await db.SaveChangesAsync();
        return password;
    }

    /// <summary>Lifts the lock after too many wrong passwords, without changing the password.</summary>
    public async Task UnlockAsync(Guid companyId, Guid userId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var user = await FindAsync(db, companyId, userId);
        user.FailedLogins = 0;
        user.LockedUntil = null;
        await db.SaveChangesAsync();
    }

    /// <summary>
    /// Deactivates (no more login) or reactivates a user. Users are never
    /// deleted: the history keeps who did what. You cannot deactivate yourself.
    /// </summary>
    public async Task SetActiveAsync(Guid companyId, Guid actingUserId, Guid userId, bool active)
    {
        if (!active && userId == actingUserId)
            throw new AdminException("You cannot deactivate yourself.");

        await using var db = await dbFactory.CreateDbContextAsync();
        var user = await FindAsync(db, companyId, userId);
        user.IsActive = active;
        await db.SaveChangesAsync();
    }

    // ------------------------------------------------------------------

    /// <summary>Emails are compared without case or spaces: "Ana@X.com " = "ana@x.com".</summary>
    public static string Normalize(string email) => email.Trim().ToLowerInvariant();

    // A company Admin hands out company roles only; SuperAdmin is TruckGo's
    private static void CheckRole(UserRole role)
    {
        if (role == UserRole.SuperAdmin) throw new AdminException("This role cannot be given here.");
    }

    // Finding the user INSIDE the company is what keeps companies apart
    private static async Task<BackOfficeUser> FindAsync(TruckGoDb db, Guid companyId, Guid userId) =>
        await db.Users.FirstOrDefaultAsync(u => u.Id == userId && u.CompanyId == companyId)
        ?? throw new AdminException("This user does not exist.");
}
