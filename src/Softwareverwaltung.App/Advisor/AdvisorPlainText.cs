using System.Text.RegularExpressions;

namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// Macht aus der Antwort des Modells reinen Text für die Seitenleiste: kein Markdown, keine klickbaren Links.
/// Häufige Formatzeichen (Überschriften, Fett, Code) fallen weg, Links werden zu „Text (Adresse)“, und
/// Denkblöcke mancher Modelle (&lt;think&gt;…&lt;/think&gt;) werden nicht angezeigt.
/// </summary>
public static partial class AdvisorPlainText
{
    public static string From(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return "";
        }
        var s = ThinkBlock().Replace(text.Replace("\r\n", "\n"), "");
        var lines = new List<string>();
        foreach (var raw in s.Split('\n'))
        {
            if (raw.TrimStart().StartsWith("```", StringComparison.Ordinal))
            {
                continue;
            }
            var line = Heading().Replace(raw, "");
            line = Link().Replace(line, m => m.Groups["text"].Value == m.Groups["url"].Value
                ? m.Groups["url"].Value
                : $"{m.Groups["text"].Value} ({m.Groups["url"].Value})");
            line = line.Replace("**", "").Replace("__", "").Replace("`", "");
            line = Bullet().Replace(line, "${indent}• ");
            lines.Add(line.TrimEnd());
        }
        return MultipleBlankLines().Replace(string.Join("\n", lines), "\n\n").Trim();
    }

    [GeneratedRegex(@"<think>[\s\S]*?(</think>|$)", RegexOptions.IgnoreCase)]
    private static partial Regex ThinkBlock();

    [GeneratedRegex(@"^\s{0,3}#{1,6}\s+")]
    private static partial Regex Heading();

    [GeneratedRegex(@"\[(?<text>[^\]]+)\]\((?<url>[^)\s]+)\)")]
    private static partial Regex Link();

    [GeneratedRegex(@"^(?<indent>\s*)[*+-]\s+")]
    private static partial Regex Bullet();

    [GeneratedRegex(@"\n{3,}")]
    private static partial Regex MultipleBlankLines();
}
