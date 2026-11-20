using System.Globalization;
using System.Windows;
using System.Windows.Data;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Converters;

public sealed class RatingToTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value switch
    {
        Rating.Red => AppText.Get("RatingRed"),
        Rating.Yellow => AppText.Get("RatingYellow"),
        Rating.Green => AppText.Get("RatingGreen"),
        _ => AppText.Get("RatingGray"),
    };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>Sichtbar, wenn eine Anzahl größer als 0 ist.</summary>
public sealed class CountToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture) =>
        value is int count && count > 0 ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>
/// Symbol eines Knopfs, der Administratorrechte braucht: bei true das Schild, sonst das Symbol aus dem Parameter
/// (Name aus SymbolRegular, z. B. "Delete24"). Unbekannter Parameter: Schild nur bei true, sonst kein Symbol.
/// </summary>
public sealed class ElevationSymbolConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Wpf.Ui.Controls.SymbolRegular.Shield24
        : Enum.TryParse<Wpf.Ui.Controls.SymbolRegular>(parameter as string, out var symbol) ? symbol
        : Wpf.Ui.Controls.SymbolRegular.Empty;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture) =>
        value is null or "" ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
