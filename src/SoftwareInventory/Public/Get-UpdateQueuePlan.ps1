function Get-UpdateQueuePlan {
    <#
    .SYNOPSIS
        Plant eine Update-Warteschlange: je Programm der genaue Befehl, die Rechte und ob es ausführbar ist.
    .DESCRIPTION
        Führt nichts aus und protokolliert nichts (wie -WhatIf). Die App zeigt das Ergebnis in der
        gemeinsamen Bestätigung, gruppiert nach „ohne Administratorrechte“, „mit Administratorrechten“
        und „nicht ausführbar“. Unconfirmed kennzeichnet neueste Versionen aus unbestätigter Quelle
        (z. B. winget-Suche nach Name). Nicht ausführbare Einträge nennen Result (Code) und Message.
        Die Warteschlange gilt nur für Updates; Deinstallieren bleibt einzeln.
    .EXAMPLE
        $plan = Get-SoftwareInventory | Get-SecurityRating | Where-Object { $_.UpdateStatus.Status -eq 'Outdated' } | Get-UpdateQueuePlan
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.UpdateQueueEntry')]
    param(
        # Ergebnisse von Get-SecurityRating oder Datensätze
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    begin {
        $index = 0
        # Nur planen: Resolve-SoftwareAction protokolliert unter -WhatIf nichts.
        $WhatIfPreference = $true
    }
    process {
        foreach ($item in $InputObject) {
            if ($null -eq $item) { continue }
            $prepared = Resolve-SoftwareAction -Action Update -InputObject $item -RestorePoint $false
            if (-not $prepared) { continue }
            $plan = $prepared.Plan
            $update = Get-RecordValue $item 'UpdateStatus'
            $latest = Get-RecordValue $item 'LatestVersion'
            if (-not $latest -and $update) { $latest = Get-RecordValue $update 'LatestVersion' }
            [pscustomobject] [ordered]@{
                PSTypeName       = 'SoftwareInventory.UpdateQueueEntry'
                Index            = $index++
                Name             = $plan.Name
                InstalledVersion = $prepared.Record.Version
                LatestVersion    = $latest
                Unconfirmed      = [bool] ($update -and $update.PSObject.Properties['Confirmed'] -and -not $update.Confirmed)
                Executable       = -not $plan.Result
                Elevated         = [bool] $plan.Elevated
                Method           = $plan.Method
                CommandLine      = $plan.CommandLine
                Result           = $plan.Result     # Code, wenn nicht ausführbar (z. B. ManualUpdateRequired)
                Message          = $plan.Message
                VendorUrl        = $plan.VendorUrl
                InputObject      = $item
            }
        }
    }
}
