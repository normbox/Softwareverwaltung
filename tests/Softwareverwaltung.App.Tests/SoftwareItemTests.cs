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
    public void ShowsTextOfModuleMessages()
    {
        // Das Modul liefert Gründe und Hinweise als Meldung mit Code, Args und Text; angezeigt wird Text.
        static System.Management.Automation.PSObject Message(string code, string text, params object[] args) => Ps(("Code", code), ("Args", args), ("Text", text));
        var item = SoftwareItem.FromRating(Ps(
            ("Name", "7-Zip 26.05 (x64)"), ("Rating", "Yellow"),
            ("Reasons", new object[] { Message("PossiblyAffectedKev", "Möglicherweise betroffen: CVE-2025-0411 (aktiv ausgenutzt, Version nicht prüfbar (Dienst NVD nicht aktiviert))", "CVE-2025-0411") }),
            ("VulnerabilityStatus", Ps(("Status", "Unknown"),
                ("Vulnerabilities", new object[] { Ps(("CveId", "CVE-2025-0411"), ("Assessment", "PossiblyAffected"), ("Kev", true),
                    ("Note", Message("KevNvdDisabled", "Version nicht prüfbar (Dienst NVD nicht aktiviert)"))) }),
                ("Refuted", new object[] { Ps(("CveId", "CVE-2025-0001"), ("Source", "NVD"), ("Note", Message("KevRefutedNvd", "KEV-Treffer CVE-2025-0001 widerlegt: Version 26.05 laut NVD nicht betroffen", "CVE-2025-0001", "26.05"))) })))));

        Assert.Equal(["Möglicherweise betroffen: CVE-2025-0411 (aktiv ausgenutzt, Version nicht prüfbar (Dienst NVD nicht aktiviert))"], item.Reasons);
        Assert.Equal("Version nicht prüfbar (Dienst NVD nicht aktiviert)", Assert.Single(item.Vulnerabilities).Note);
        Assert.Equal("KEV-Treffer CVE-2025-0001 widerlegt: Version 26.05 laut NVD nicht betroffen", Assert.Single(item.Refuted));
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
    [Fact]
    public void ShowsEachSourceSeparatelyWithAttribution()
    {
        var vuln = VulnerabilityItem.FromPs(Ps(
            ("CveId", "CVE-2026-1001"), ("Assessment", "PossiblyAffected"),
            ("Sources", new object[]
            {
                Ps(("Source", "NVD"), ("Verdict", "Affected"), ("Range", "< 24.09"), ("Attribution", Ps(("Code", "AttributionNVD"), ("Text", "Daten: National Vulnerability Database (NIST)"))),
                   ("Url", "https://nvd.nist.gov/vuln/detail/CVE-2026-1001")),
                Ps(("Source", "CIRCL"), ("Verdict", "NotAffected"), ("Range", "< 24.0"), ("Attribution", Ps(("Code", "AttributionCIRCL"), ("Text", "Daten: CVE-Programm über CIRCL, CC BY 4.0"))),
                   ("Url", "https://vulnerability.circl.lu/vuln/CVE-2026-1001")),
                Ps(("Source", "CIRCL"), ("Verdict", "Unknown"), ("Url", "http://unsicher.example/x")),
            })));

        Assert.Equal(3, vuln.Sources.Count);
        Assert.Equal("NVD: betroffen (Bereich < 24.09)", vuln.Sources[0].Line);
        Assert.Equal("CIRCL: nicht betroffen (Bereich < 24.0)", vuln.Sources[1].Line);
        Assert.Equal("Daten: CVE-Programm über CIRCL, CC BY 4.0", vuln.Sources[1].Attribution);
        Assert.Equal(new Uri("https://vulnerability.circl.lu/vuln/CVE-2026-1001"), vuln.Sources[1].Url);
        Assert.Equal("CIRCL: in dieser Quelle nicht bekannt", vuln.Sources[2].Line);
        Assert.Null(vuln.Sources[2].Url);   // nur https
    }

    [Fact]
    public void CompactLineShowsShortAssessmentAndOneSymbolPerSource()
    {
        var vuln = VulnerabilityItem.FromPs(Ps(
            ("CveId", "CVE-2026-1002"), ("Assessment", "PossiblyAffected"), ("Score", 9.3),
            ("Sources", new object[]
            {
                Ps(("Source", "NVD"), ("Verdict", "Unknown"), ("Attribution", "Daten: National Vulnerability Database (NIST)")),
                Ps(("Source", "CIRCL"), ("Verdict", "NotEvaluable"), ("Attribution", "Daten: CVE-Programm über CIRCL, CC BY 4.0")),
            })));

        Assert.Equal("möglich", vuln.AssessmentShort);
        Assert.Equal("CVSS 9.3", vuln.ScoreText);
        Assert.Equal(["NVD –", "CIRCL ?"], vuln.Sources.Select(s => s.ShortText));
        // Aufgeklappt nur, was die Kopfzeile nicht zeigt: EPSS
        Assert.Null(vuln.EpssText);
        Assert.Equal("Ausnutzungswahrscheinlichkeit (EPSS): 67 %",
            VulnerabilityItem.FromPs(Ps(("CveId", "CVE-4"), ("Assessment", "Affected"), ("Epss", 0.67))).EpssText);
        Assert.Equal("betroffen", VulnerabilityItem.FromPs(Ps(("CveId", "CVE-3"), ("Assessment", "Affected"))).AssessmentShort);
        Assert.Equal("✓", new SourceStatementItem("NVD", "Affected", null, null, null, null).Symbol);
        Assert.Equal("✗", new SourceStatementItem("NVD", "NotAffected", null, null, null, null).Symbol);
    }

    [Fact]
    public void DetailsShowThreeReasonsAndNameEachSourceOnceBelowTheList()
    {
        var source = (string name, string text) => Ps(("Source", name), ("Verdict", "Affected"), ("Attribution", text));
        var rating = Ps(
            ("Name", "FFmpeg"),
            ("Reasons", new object[] { "Grund 1", "Grund 2", "Grund 3", "Grund 4", "Grund 5" }),
            ("VulnerabilityStatus", Ps(("Status", "Checked"), ("Vulnerabilities", new object[]
            {
                Ps(("CveId", "CVE-1"), ("Assessment", "Affected"), ("Sources", new object[] { source("NVD", "Daten: NVD"), source("CIRCL", "Daten: CIRCL") })),
                Ps(("CveId", "CVE-2"), ("Assessment", "Affected"), ("Sources", new object[] { source("CIRCL", "Daten: CIRCL") })),
            }))));

        var item = SoftwareItem.FromRating(rating);

        Assert.Equal(["Grund 1", "Grund 2", "Grund 3"], item.ReasonsShown);
        Assert.Equal(["Grund 4", "Grund 5"], item.ReasonsMore);
        Assert.Equal("2 weitere Gründe", item.ReasonsMoreText);
        Assert.Equal(["Daten: NVD", "Daten: CIRCL"], item.Attributions);

        var four = SoftwareItem.FromRating(Ps(("Name", "X"), ("Reasons", new object[] { "a", "b", "c", "d" })));
        Assert.Equal("1 weiterer Grund", four.ReasonsMoreText);
        Assert.Null(SoftwareItem.FromRating(Ps(("Name", "Y"), ("Reasons", new object[] { "a" }))).ReasonsMoreText);
    }
}
