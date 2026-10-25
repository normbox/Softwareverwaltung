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
