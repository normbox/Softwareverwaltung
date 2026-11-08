function Remove-HelperCopy {
    <#
    .SYNOPSIS
        Entfernt den ganzen Ordner mit der geschützten Kopie des Helfers (eine UAC-Abfrage).
    .DESCRIPTION
        Läuft über ein Werkzeug aus System32, denn die Exe kann ihren eigenen Ordner nicht löschen. Der Ordner
        „Softwareverwaltung“ darüber verschwindet nur, wenn er danach leer ist. Beim nächsten Update legt
        die App die Kopie wieder an.
    .OUTPUTS
        Result: Removed, NotPresent, ElevationDenied oder Failed; dazu Message.
    .EXAMPLE
        Remove-HelperCopy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('SoftwareInventory.HelperCopyRemoval')]
    param()
    $root = Get-HelperCopyRoot
    $finish = {
        param($Result, $Message)
        [pscustomobject] @{ PSTypeName = 'SoftwareInventory.HelperCopyRemoval'; Result = $Result; Message = $Message; Path = $root }
    }
    if (-not (Test-Path -LiteralPath $root)) { return & $finish 'NotPresent' $null }
    if (-not $PSCmdlet.ShouldProcess($root, (Get-LocalizedString 'HelperCopyRemoveAction'))) { return & $finish 'NotPresent' $null }

    # /d: Keine AutoRun-Befehle aus der Registry des Benutzers im erhöhten Prozess.
    $arguments = '/d /c rd /s /q "{0}" & rd "{1}"' -f $root, (Split-Path -Parent $root)
    try { [void] (Invoke-ElevatedSystemTool -Tool 'cmd.exe' -Arguments $arguments) }
    catch {
        if (Test-ElevationCancelled $_) { return & $finish 'ElevationDenied' (New-InventoryMessage ElevationDenied) }
        Write-HelperCopyLog -Action 'RemoveHelperCopy' -Result 'Failed' -Message (New-InventoryMessage HelperCopyRemoveFailed $root) -Path $root
        return & $finish 'Failed' (New-InventoryMessage HelperCopyRemoveFailed $root)
    }
    if (Test-Path -LiteralPath $root) {
        $message = New-InventoryMessage HelperCopyRemoveFailed $root
        Write-HelperCopyLog -Action 'RemoveHelperCopy' -Result 'Failed' -Message $message -Path $root
        return & $finish 'Failed' $message
    }
    $message = New-InventoryMessage HelperCopyRemoved
    Write-HelperCopyLog -Action 'RemoveHelperCopy' -Result 'Succeeded' -Message $message -Path $root
    & $finish 'Removed' $message
}
