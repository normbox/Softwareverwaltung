using System.Management.Automation;

namespace Softwareverwaltung.App.Models;

/// <summary>
/// Abbild von Get-InventorySetting. Switches enthält alle Schalter der Gruppen Sources, Traces,
/// Services und Actions mit ihrem Modulnamen (z. B. „RegistryMachine“, „NVD“, „RestorePoint“).
/// </summary>
public sealed record AppSettings
{
    public static readonly string[] SwitchGroups = ["Sources", "Traces", "Services", "Actions"];

    public string? Usage { get; init; }
    public IReadOnlyDictionary<string, bool> Switches { get; init; } = new Dictionary<string, bool>();
    public IReadOnlyList<string> ScanPaths { get; init; } = [];
    public IReadOnlyList<string> ScanDrives { get; init; } = [];
    public IReadOnlyList<string> ExcludePaths { get; init; } = [];
    public bool IncludeTemp { get; init; }
    public bool ComputeHash { get; init; }
    public bool SmartExclusions { get; init; } = true;
    public int LogRetentionDays { get; init; } = 30;
    public int LogMaxSizeMB { get; init; } = 100;

    public static AppSettings FromPs(PSObject obj)
    {
        var switches = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (var group in SwitchGroups)
        {
            if (obj.Properties[group]?.Value is PSObject values)
            {
                foreach (var property in values.Properties)
                {
                    switches[property.Name] = property.Value is true;
                }
            }
        }
        var fileScan = obj.Properties["FileScan"]?.Value as PSObject;
        var maintenance = obj.Properties["Maintenance"]?.Value as PSObject;
        return new AppSettings
        {
            Usage = obj.Properties["Usage"]?.Value?.ToString(),
            Switches = switches,
            ScanPaths = Strings(fileScan, "Paths"),
            ScanDrives = Strings(fileScan, "Drives"),
            ExcludePaths = Strings(fileScan, "ExcludePaths"),
            IncludeTemp = fileScan?.Properties["IncludeTemp"]?.Value is true,
            ComputeHash = fileScan?.Properties["ComputeHash"]?.Value is true,
            SmartExclusions = fileScan?.Properties["SmartExclusions"]?.Value is not false,
            LogRetentionDays = Convert.ToInt32(maintenance?.Properties["LogRetentionDays"]?.Value ?? 30),
            LogMaxSizeMB = Convert.ToInt32(maintenance?.Properties["LogMaxSizeMB"]?.Value ?? 100),
        };
    }

    internal static IReadOnlyList<string> Strings(PSObject? obj, string name) => obj?.Properties[name]?.Value switch
    {
        null => [],
        string single => [single],
        PSObject { BaseObject: string single } => [single],
        System.Collections.IEnumerable many => many.Cast<object?>().Select(v => v?.ToString()).OfType<string>().Where(s => s.Length > 0).ToList(),
        var other => [other.ToString()!],
    };
}

/// <summary>Werte einer Vorlage aus Get-SettingPreset; die App belegt damit nur vor.</summary>
public sealed record SettingPreset(IReadOnlyList<string> Enable, IReadOnlyList<string> ScanPaths, IReadOnlyList<string> ScanDrives, bool IncludeTemp, bool ComputeHash)
{
    public static SettingPreset FromPs(PSObject obj)
    {
        var fileScan = obj.Properties["FileScan"]?.Value as PSObject;
        return new SettingPreset(
            AppSettings.Strings(obj, "Enable"),
            AppSettings.Strings(fileScan, "Paths"),
            AppSettings.Strings(fileScan, "Drives"),
            fileScan?.Properties["IncludeTemp"]?.Value is true,
            fileScan?.Properties["ComputeHash"]?.Value is true);
    }
}

/// <summary>Laufwerk aus Get-ScanDrive.</summary>
public sealed record ScanDrive(string Drive, string? Label, long SizeGB, bool IsDefault)
{
    public static ScanDrive FromPs(PSObject obj) => new(
        obj.Properties["Drive"]?.Value?.ToString() ?? "",
        obj.Properties["Label"]?.Value?.ToString(),
        Convert.ToInt64(obj.Properties["SizeGB"]?.Value ?? 0),
        obj.Properties["IsDefault"]?.Value is true);
}

/// <summary>Status aus Get-ServiceCredentialStatus. Enthält nie den Schlüssel selbst.</summary>
public sealed record CredentialStatus(string Service, bool Stored, string? EnvironmentVariable, bool EnvironmentSet, string? Source)
{
    public static CredentialStatus FromPs(PSObject obj) => new(
        obj.Properties["Service"]?.Value?.ToString() ?? "",
        obj.Properties["Stored"]?.Value is true,
        obj.Properties["EnvironmentVariable"]?.Value?.ToString(),
        obj.Properties["EnvironmentSet"]?.Value is true,
        obj.Properties["Source"]?.Value?.ToString());
}
