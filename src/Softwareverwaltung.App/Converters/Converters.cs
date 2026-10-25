using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Converters;

/// <summary>Ampelfarbe. Die Farbe steht nie allein, daneben steht immer der Text (Barrierefreiheit).</summary>
public sealed class RatingToBrushConverter : IValueConverter
{
    private static readonly Brush Red = Freeze(new SolidColorBrush(Color.FromRgb(0xC4, 0x2B, 0x1C)));
    private static readonly Brush Yellow = Freeze(new SolidColorBrush(Color.FromRgb(0xE0, 0xA1, 0x00)));
    private static readonly Brush Green = Freeze(new SolidColorBrush(Color.FromRgb(0x10, 0x7C, 0x10)));
    private static readonly Brush Gray = Freeze(new SolidColorBrush(Color.FromRgb(0x8A, 0x8A, 0x8A)));

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value switch
    {
        Rating.Red => Red,
        Rating.Yellow => Yellow,
        Rating.Green => Green,
        _ => Gray,
    };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();

    private static Brush Freeze(Brush brush)
    {
        brush.Freeze();
        return brush;
    }
}

public sealed class RatingToTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value switch
    {
        Rating.Red => "Rot",
        Rating.Yellow => "Gelb",
        Rating.Green => "Grün",
        _ => "Grau",
    };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture) =>
        value is null ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
