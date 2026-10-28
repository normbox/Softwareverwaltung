# Vereinbarung der winget-Quelle „msstore“: Der Benutzer stimmt einmal ausdrücklich zu, erst dann gibt die
# App --accept-source-agreements weiter (nie still im Befehl).

$script:StoreTermsUrl = 'https://aka.ms/microsoft-store-terms-of-transaction'

function Test-StoreAgreementAccepted {
    param($Setting = (Read-InventorySetting))
    [bool] ($Setting.PSObject.Properties['Agreements'] -and $Setting.Agreements -and $Setting.Agreements.MsStore)
}
