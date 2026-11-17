using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Strenge Prüfung einer .reg-Sicherung im Helfer. Die Fälle stehen in tests/Data/registry-backup-cases.json und
/// gelten ebenso für das Modul (Test-RegistryBackupContent): Beide müssen dasselbe Ergebnis liefern.
/// </summary>
public sealed class RegistryBackupRulesTests
{
    private static string TestFolder([CallerFilePath] string sourceFile = "") => Path.GetDirectoryName(Path.GetDirectoryName(sourceFile)!)!;

    [Fact]
    public void MatchesTheSharedTableWithTheModule()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(TestFolder(), "Data", "registry-backup-cases.json")));
        var root = doc.RootElement;
        var header = root.GetProperty("header").GetString()!;
        var locations = root.GetProperty("locations").EnumerateArray()
            .Select(l => (Placeholder: l.GetProperty("placeholder").GetString()!, Location: new UninstallLocation(l.GetProperty("nativePath").GetString()!, l.GetProperty("scope").GetString()!)))
            .ToList();
        // {U+XXXX} wird zum Zeichen mit diesem Codepunkt (unsichtbare Zeichen stehen in der Tabelle nie als Escape-Text).
        string Expand(string text) => Regex.Replace(
            locations.Aggregate(text.Replace("{H}", header), (t, l) => t.Replace(l.Placeholder, l.Location.NativePath)),
            @"\{U\+([0-9A-Fa-f]{4})\}",
            m => ((char)Convert.ToInt32(m.Groups[1].Value, 16)).ToString());

        var cases = root.GetProperty("cases").EnumerateArray().ToList();
        Assert.True(cases.Count > 25);
        var wrong = new List<string>();
        foreach (var c in cases)
        {
            var expected = c.GetProperty("expected").ValueKind == JsonValueKind.Null ? null : c.GetProperty("expected").GetString();
            var actual = RegistryBackupRules.CheckContent(
                Expand(c.GetProperty("text").GetString()!), Expand(c.GetProperty("key").GetString()!), c.GetProperty("scope").GetString()!, locations.Select(l => l.Location));
            if (actual != expected)
            {
                wrong.Add($"{c.GetProperty("name").GetString()}: erwartet {expected ?? "null"}, war {actual ?? "null"}");
            }
        }
        Assert.Empty(wrong);
    }

    [Fact]
    public void NullOrEmptyInputIsRefused()
    {
        var none = Array.Empty<UninstallLocation>();
        Assert.Equal("Empty", RegistryBackupRules.CheckContent(null!, "x", "User", none));
        Assert.Equal("Empty", RegistryBackupRules.CheckContent("x", "", "User", none));
    }

    [Fact]
    public void ReadsTheBytesOfABackupLikeTheModule()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(TestFolder(), "Data", "registry-backup-cases.json")));
        var cases = doc.RootElement.GetProperty("fileCases").EnumerateArray().ToList();
        Assert.True(cases.Count > 8);
        var wrong = new List<string>();
        foreach (var c in cases)
        {
            // Ohne Convert.FromHexString: Die Datei läuft auch im net472-Testprojekt (SoftwareInventory.Helper.Tests).
            var hex = c.GetProperty("hex").GetString()!;
            var bytes = Enumerable.Range(0, hex.Length / 2).Select(i => Convert.ToByte(hex.Substring(i * 2, 2), 16)).ToArray();
            var code = BackupFileRules.DecodeText(bytes, out var text);
            var expectedCode = c.GetProperty("expectedCode").ValueKind == JsonValueKind.Null ? null : c.GetProperty("expectedCode").GetString();
            var expectedText = c.TryGetProperty("expectedText", out var t)
                ? Regex.Replace(t.GetString()!, @"\{U\+([0-9A-Fa-f]{4})\}", m => ((char)Convert.ToInt32(m.Groups[1].Value, 16)).ToString())
                : null;
            if (code != expectedCode || (expectedCode is null && text != expectedText))
            {
                wrong.Add($"{c.GetProperty("name").GetString()}: erwartet {expectedCode ?? "null"}/{expectedText}, war {code ?? "null"}/{text}");
            }
        }
        Assert.Empty(wrong);
    }

    [Fact]
    public void RefusesABackupOver16MegabytesEvenWithAValidByteOrderMark()
    {
        var big = new byte[BackupFileRules.MaxBytes + 2];
        big[0] = 0xFF;
        big[1] = 0xFE;
        Assert.Equal("TooLarge", BackupFileRules.DecodeText(big, out var text));
        Assert.Null(text);
    }
}
