using Softwareverwaltung.App.Models;
using static Softwareverwaltung.App.Tests.TestHelpers;

namespace Softwareverwaltung.App.Tests;

public sealed class SoftwareItemTests
{
    [Fact]
    public void MapsSecurityRatingFields()
    {
        var rating = Ps(
            ("Name", "7-Zip 24.09"),
            ("Version", "24.09"),
            ("Rating", "Yellow"),
            ("Reasons", new object[] { "Update verfügbar: 26.05", "Dienst NVD nicht aktiviert" }),
            ("LatestVersion", "26.05"),
            ("UpdateStatus", Ps(("Status", "Outdated"), ("Confirmed", true))),
            ("VulnerabilityStatus", Ps(("Status", "Checked"), ("Vulnerabilities", new object[]
            {
                Ps(("CveId", "CVE-1"), ("Assessment", "Affected")),
                Ps(("CveId", "CVE-2"), ("Assessment", "Informational")),
            }))),
            ("Record", Ps(("Publisher", "Igor Pavlov"), ("Sources", new[] { "Registry", "Winget" }))));

        var item = SoftwareItem.FromRating(rating);

        Assert.Equal("7-Zip 24.09", item.Name);
        Assert.Equal("Igor Pavlov", item.Publisher);
        Assert.Equal("24.09", item.InstalledVersion);
        Assert.Equal("26.05", item.LatestVersion);
        Assert.False(item.LatestVersionUnconfirmed);
        Assert.True(item.UpdateAvailable);
        Assert.Equal(Rating.Yellow, item.Rating);
        Assert.Equal(["Update verfügbar: 26.05", "Dienst NVD nicht aktiviert"], item.Reasons);
        Assert.Equal(1, item.VulnerabilityCount);
        Assert.True(item.HasSecurityRisk);
        Assert.Equal("Registry, Winget", item.Sources);
        Assert.Same(rating, item.Source);
    }

    [Fact]
    public void LeavesVulnerabilityCountEmptyWhenNotChecked()
    {
        var item = SoftwareItem.FromRating(Ps(
            ("Name", "Tool"), ("Rating", "Gray"), ("Reasons", "keine CPE gefunden"),
            ("VulnerabilityStatus", Ps(("Status", "Unknown"), ("Vulnerabilities", Array.Empty<object>())))));

        Assert.Null(item.VulnerabilityCount);
        Assert.False(item.HasSecurityRisk);
        Assert.Equal(Rating.Gray, item.Rating);
        Assert.Equal(["keine CPE gefunden"], item.Reasons);
    }

    [Fact]
    public void CountsPossiblyAffectedEvenWithoutFullCheck()
    {
        // Fall 7-Zip mit nur KEV: NVD aus, KEV-Treffer ohne prüfbare Version → Gelb.
        var item = SoftwareItem.FromRating(Ps(
            ("Name", "7-Zip 26.05 (x64)"), ("Rating", "Yellow"),
            ("Reasons", new object[] { "Möglicherweise betroffen: CVE-2025-0411 (aktiv ausgenutzt, Version nicht prüfbar (Dienst NVD nicht aktiviert))" }),
            ("VulnerabilityStatus", Ps(("Status", "Unknown"), ("Vulnerabilities", new object[]
            {
                Ps(("CveId", "CVE-2025-0411"), ("Assessment", "PossiblyAffected"), ("Kev", true), ("Score", 7.0), ("Epss", 0.67071),
                   ("Note", "Aktiv ausgenutzt; Version nicht prüfbar (Dienst NVD nicht aktiviert)"), ("Url", "https://nvd.nist.gov/vuln/detail/CVE-2025-0411")),
            })))));

        Assert.Equal(1, item.VulnerabilityCount);
        Assert.Equal(1, item.PossibleCount);
        Assert.Equal("1 möglich", item.VulnerabilityText);
        Assert.True(item.HasSecurityRisk);
        Assert.StartsWith("Möglicherweise betroffen: CVE-2025-0411", item.ReasonSummary);
        var vuln = Assert.Single(item.Vulnerabilities);
        Assert.Equal("möglicherweise betroffen · aktiv ausgenutzt (KEV) · CVSS 7.0 · EPSS 67 %", vuln.Summary);
        Assert.Equal(new Uri("https://nvd.nist.gov/vuln/detail/CVE-2025-0411"), vuln.Url);
    }

    [Theory]
    [InlineData(new[] { "Affected", "Affected" }, "2")]
    [InlineData(new[] { "Affected", "PossiblyAffected", "Informational" }, "1 + 1 möglich")]
    [InlineData(new string[0], "0")]
    public void FormatsVulnerabilityColumn(string[] assessments, string expected)
    {
        var item = SoftwareItem.FromRating(Ps(
            ("Name", "Tool"), ("Rating", "Yellow"),
            ("VulnerabilityStatus", Ps(("Status", "Checked"), ("Vulnerabilities", assessments.Select(a => (object)Ps(("CveId", "CVE-1"), ("Assessment", a))).ToArray())))));

        Assert.Equal(expected, item.VulnerabilityText);
    }

    [Fact]
    public void ShowsRefutedKevHitsAndAllReasons()
    {
        var item = SoftwareItem.FromRating(Ps(
            ("Name", "7-Zip 26.05 (x64)"), ("Rating", "Gray"),
            ("Reasons", new object[] { "Nicht auf Lücken geprüft: Dienst NVD nicht aktiviert", "KEV-Treffer CVE-2025-0411 widerlegt: behoben ab 24.09 (Katalog), installiert 26.05", "Version aktuell" }),
            ("VulnerabilityStatus", Ps(("Status", "Unknown"), ("Vulnerabilities", Array.Empty<object>()),
                ("Refuted", new object[] { Ps(("CveId", "CVE-2025-0411"), ("Source", "Catalog"), ("Note", "KEV-Treffer CVE-2025-0411 widerlegt: behoben ab 24.09 (Katalog), installiert 26.05")) })))));

        Assert.Null(item.VulnerabilityCount);
        Assert.Equal("", item.VulnerabilityText);
        Assert.False(item.HasSecurityRisk);
        Assert.Equal("Nicht auf Lücken geprüft: Dienst NVD nicht aktiviert (+2)", item.ReasonSummary);
        Assert.Contains("behoben ab 24.09", Assert.Single(item.Refuted));
    }

    [Fact]
    public void MarksUnconfirmedLatestVersion()
    {
        var item = SoftwareItem.FromRating(Ps(
            ("Name", "Tool"), ("Rating", "Yellow"), ("LatestVersion", "2.0"),
            ("UpdateStatus", Ps(("Status", "Outdated"), ("Confirmed", false)))));

        Assert.True(item.LatestVersionUnconfirmed);
    }

    [Fact]
    public void ToleratesMissingFields()
    {
        var item = SoftwareItem.FromRating(Ps(("Name", null), ("Rating", "Unbekannt")));

        Assert.Equal("(ohne Namen)", item.Name);
        Assert.Equal(Rating.Gray, item.Rating);
        Assert.Empty(item.Reasons);
        Assert.Equal("", item.Sources);
        Assert.False(item.UpdateAvailable);
    }
}
