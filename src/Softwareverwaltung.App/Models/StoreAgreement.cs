using System.Management.Automation;

namespace Softwareverwaltung.App.Models;

/// <summary>Abbild von SoftwareInventory.StoreAgreementNotice: Text der Vereinbarung der Quelle „msstore“ und Link.</summary>
public sealed record StoreAgreement(string Text, Uri? Url)
{
    public static StoreAgreement FromPs(PSObject obj) => new(
        ActionOutcome.Text(obj, "Text") ?? "",
        Uri.TryCreate(ActionOutcome.Text(obj, "Url"), UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri : null);
}
