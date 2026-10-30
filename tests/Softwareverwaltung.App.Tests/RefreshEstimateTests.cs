using System.Management.Automation;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Tests;

public class RefreshEstimateTests
{
    [Fact]
    public void ReadsTheConfirmReasonFromTheModule()
    {
        var obj = new PSObject();
        obj.Properties.Add(new PSNoteProperty("NvdRequests", 126));
        obj.Properties.Add(new PSNoteProperty("Seconds", 1703));
        obj.Properties.Add(new PSNoteProperty("NeedsConfirmation", true));
        obj.Properties.Add(new PSNoteProperty("ConfirmReason", "LongDuration"));

        var estimate = RefreshEstimate.FromPs(obj);

        Assert.True(estimate.NeedsConfirmation);
        Assert.Equal(RefreshEstimate.ReasonLongDuration, estimate.ConfirmReason);
        Assert.Equal("etwa 29 Minuten", estimate.DurationText);
        Assert.Equal("Ein Scan ohne Zwischenspeicher dauert etwa 29 Minuten. Fortfahren?", AppText.Format("RefreshLongText", estimate.DurationText));
    }

    [Fact]
    public void ShortDurationsAreShownInSeconds()
    {
        Assert.Equal("etwa 72 Sekunden", new RefreshEstimate(12, 72, NeedsConfirmation: true).DurationText);
        Assert.Null(new RefreshEstimate(12, 72, NeedsConfirmation: true).ConfirmReason);
    }
}
