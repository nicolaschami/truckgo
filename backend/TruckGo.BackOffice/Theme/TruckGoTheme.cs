using MudBlazor;

namespace TruckGo.BackOffice.Theme;

/// <summary>
/// The look of the back office, in one place: colours, font, corners.
///
///   navy   #0B1F3A  — the side menu and the login panel (calm, "control room")
///   blue   #2563EB  — actions: buttons, links, the selected menu item
///   amber  #F59E0B  — the TruckGo brand mark and warnings
///
/// The finer touches MudBlazor has no setting for are in wwwroot/app.css.
/// </summary>
public static class TruckGoTheme
{
    public const string Navy = "#0B1F3A";
    public const string Blue = "#2563EB";
    public const string Amber = "#F59E0B";

    private static readonly string[] Font = ["Inter", "Segoe UI", "Roboto", "Arial", "sans-serif"];

    public static readonly MudTheme Theme = new()
    {
        PaletteLight = new PaletteLight
        {
            Primary = Blue,
            Secondary = "#7C3AED",
            Info = "#0EA5E9",
            Success = "#16A34A",
            Warning = Amber,
            Error = "#DC2626",

            Background = "#F4F6FA",   // page behind the cards
            Surface = "#FFFFFF",      // cards, tables, dialogs
            TextPrimary = "#0F172A",
            TextSecondary = "#64748B",
            LinesDefault = "#E2E8F0",
            TableLines = "#EEF2F6",
            LinesInputs = "#CBD5E1",

            AppbarBackground = "#FFFFFF",
            AppbarText = "#0F172A",
            DrawerBackground = Navy,
            DrawerText = "#CBD5E1",
            DrawerIcon = "#94A3B8",
        },
        LayoutProperties = new LayoutProperties
        {
            DefaultBorderRadius = "10px",
            DrawerWidthLeft = "248px",
            DrawerMiniWidthLeft = "72px", // the folded menu: icons only
            AppbarHeight = "60px",
        },
        Typography = new Typography
        {
            Default = new DefaultTypography { FontFamily = Font, FontSize = "0.875rem" },
            H5 = new H5Typography { FontFamily = Font, FontWeight = "700", FontSize = "1.5rem", LetterSpacing = "-0.01em" },
            H6 = new H6Typography { FontFamily = Font, FontWeight = "600", FontSize = "1.05rem" },
            Subtitle2 = new Subtitle2Typography { FontFamily = Font, FontWeight = "600" },
            // Buttons in normal case ("New user"), not SHOUTING capitals
            Button = new ButtonTypography { FontFamily = Font, FontWeight = "600", TextTransform = "none" },
            Overline = new OverlineTypography { FontFamily = Font, FontWeight = "600", LetterSpacing = "0.08em" },
        },
    };
}
