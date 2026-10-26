using System.Globalization;
using System.Resources;
using System.Windows.Markup;

namespace Softwareverwaltung.App.Localization;

/// <summary>
/// Texte der App aus Resources/Strings.resx in der Sprache der Oberfläche (siehe CLAUDE.md:
/// neue Texte nie fest im Code). Fehlt ein Schlüssel, kommt der Schlüssel selbst zurück.
/// </summary>
public static class AppText
{
    public static ResourceManager Resources { get; } = new("Softwareverwaltung.App.Resources.Strings", typeof(AppText).Assembly);

    public static string Get(string key) => Resources.GetString(key, CultureInfo.CurrentUICulture) ?? key;
}

/// <summary>XAML: Text="{loc:Text SettingsPortableTitle}".</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class TextExtension(string key) : MarkupExtension
{
    public TextExtension() : this(string.Empty)
    {
    }

    public string Key { get; set; } = key;

    public override object ProvideValue(IServiceProvider serviceProvider) => AppText.Get(Key);
}
