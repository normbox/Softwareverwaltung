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

public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture) =>
        value is null or "" ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
