# Ablageorte der App an einer Stelle (Etappe 8c „App-Daten entfernen“). Alle Pfade des Moduls zu eigenen Daten
# kommen von hier; ein Wächtertest (tests/Unit/AppData.Tests.ps1) prüft, dass sonst niemand %APPDATA% oder
# %LOCALAPPDATA% mit dem App-Ordner zusammensetzt.
#
#   Roaming  %APPDATA%\SoftwareInventory       settings.json, cpe-map.json, app-ui.json (App)
#   Local    %LOCALAPPDATA%\SoftwareInventory  logs\ (Aktionsprotokoll, Sicherungen HKCU), cache\, scans\
#   Temp     nur Dateien mit genau den Namen aus $script:AppTempFilePatterns (Reste des Helfers und des Zurückspielens)
#   Machine  Program Files\Softwareverwaltung   Helfer-Kopie und HKLM-Sicherungen (Entfernen nur mit UAC, Etappe 8c-2)
#   dazu die Einträge SoftwareInventory/<Dienst> in der Anmeldeinformationsverwaltung (Secret.ps1).

$script:AppDataFolderName = 'SoftwareInventory'
$script:AppMachineFolderName = 'Softwareverwaltung'
# Nach Remove-AppData schreiben Protokolle, Zwischenspeicher und Bereinigung nichts mehr (sonst entstünden die Ordner
# sofort neu). Gilt bis zum nächsten Laden des Moduls; die App beendet sich danach ohnehin.
$script:AppDataRemoved = $false
# Reste im Temp-Ordner: MSI-Log des Helfers (SoftwareInventory-<Nonce>.log bzw. -<Nonce>-<Schritt>.log in der
# Warteschlange, Nonce = GUID ohne Bindestriche) und die Importdatei beim Zurückspielen
# (SoftwareInventory-restore-<ActionId>.reg). Nur genau diese Namen, alles andere im Temp-Ordner bleibt.
$script:AppTempFilePatterns = @(
    '^SoftwareInventory-[0-9a-f]{32}(?:-[0-9]{1,4})?\.log\z'
    '^SoftwareInventory-restore-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.reg\z'
)
# Im Admin-Ordner gehören der App nur diese Unterordner. Den Ordner Softwareverwaltung selbst entfernt sie nur, wenn er
# danach leer ist: Ein späterer Installer könnte die App selbst dorthin legen.
$script:AppMachineSubfolders = @('Helper', 'RegistryBackup')
# Zeichen, die cmd.exe in einer Befehlszeile deutet (auch in Anführungszeichen: % und bei verzögerter Erweiterung !).
# Pfade damit gehen nie an die erhöhte cmd-Zeile.
$script:CmdUnsafePathPattern = '["%^&|<>!]'

function Test-AppDataBasePath {
    <#
    .SYNOPSIS
        Ist der Wert aus %APPDATA%/%LOCALAPPDATA% als Grundordner brauchbar?
    .DESCRIPTION
        Immer abgelehnt: leer, relativ (auch „C:ordner“ und „\ordner“), Gerätepfade (\\?\, \\.\), ungültige Zeichen.
        Mit -ForRemoval zusätzlich alles, was kein Pfad auf einem lokalen Laufwerk ist (UNC, Netzlaufwerk): Gelöscht
        wird nur dort. Für den normalen Betrieb bleiben UNC-Pfade erlaubt (Ordnerumleitung in Firmen).
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $Path, [switch] $ForRemoval)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) { return $false }
    if ($Path -match '^[\\/]{2}[?.][\\/]') { return $false }
    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) { return $false }
    if (-not $ForRemoval) { return $true }
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $false }
    if ($full -notmatch '^[A-Za-z]:\\') { return $false }
    try { $type = Get-AppDataDriveType -Path $full } catch { return $false }
    $type -in 'Fixed', 'Removable', 'Ram'
}

function Get-AppDataDriveType {
    # Art des Laufwerks (Fixed, Network …); eigene Funktion, damit Tests ein Netzlaufwerk nachstellen können.
    param([string] $Path)
    [string] [System.IO.DriveInfo]::new($Path.Substring(0, 1)).DriveType
}

function Get-AppDataRoot {
    <#
    .SYNOPSIS
        Der App-Ordner im Profil: %APPDATA%\SoftwareInventory (Roaming) oder %LOCALAPPDATA%\SoftwareInventory (Local).
    .DESCRIPTION
        Bricht mit dem Code AppDataRootInvalid ab (Exception.Data['Code']), wenn die Umgebungsvariable leer, relativ
        oder ungültig ist; mit -ForRemoval auch, wenn sie auf kein lokales Laufwerk zeigt. Mit -ForRemoval ist der
        Pfad vollständig aufgelöst (ohne „..“).
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [ValidateSet('Roaming', 'Local')] [string] $Scope, [switch] $ForRemoval)
    $variable = if ($Scope -eq 'Roaming') { 'APPDATA' } else { 'LOCALAPPDATA' }
    $value = [Environment]::GetEnvironmentVariable($variable)
    if (-not (Test-AppDataBasePath -Path $value -ForRemoval:$ForRemoval)) {
        $arguments = @($variable, [string] $value)
        $exception = [System.InvalidOperationException]::new((Get-LocalizedString 'ReasonAppDataRootInvalid' $arguments))
        $exception.Data['Code'] = 'AppDataRootInvalid'
        $exception.Data['Args'] = $arguments
        throw $exception
    }
    $base = if ($ForRemoval) { [System.IO.Path]::GetFullPath($value) } else { $value }
    [System.IO.Path]::Combine($base, $script:AppDataFolderName)
}

function Get-AppDataDirectory {
    # %LOCALAPPDATA%\SoftwareInventory (Logs, Zwischenspeicher, Scans); viele Tests ersetzen genau diese Funktion.
    Get-AppDataRoot -Scope Local
}

function Get-AppMachineDirectory {
    # Program Files\Softwareverwaltung: Helfer-Kopie (Helper\) und HKLM-Sicherungen (RegistryBackup\).
    [System.IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), $script:AppMachineFolderName)
}

function Get-AppTempDirectory {
    [System.IO.Path]::GetTempPath()
}

function Test-AppDataRemoved {
    # Wahr nach Remove-AppData: Fehlerprotokoll, Hinweise, Zwischenspeicher und Bereinigung schreiben dann still nichts.
    [bool] $script:AppDataRemoved
}

function Assert-AppDataWritable {
    <#
    .SYNOPSIS
        Bricht nach Remove-AppData mit dem Code AppDataAlreadyRemoved ab (Exception.Data['Code']).
    .DESCRIPTION
        Für alles, was Nutzdaten schreibt oder eine Aktion protokolliert: Einstellungen, CPE-Zuordnungen, Scans,
        Registry-Sicherungen und das Aktionsprotokoll. Weil jede Aktion zuerst „Started“ protokolliert, läuft nach dem
        Entfernen keine Aktion mehr an (sie bliebe sonst ohne Protokoll, CLAUDE.md „Jede Aktion wird protokolliert“).
    #>
    if (-not $script:AppDataRemoved) { return }
    $exception = [System.InvalidOperationException]::new((Get-LocalizedString 'ReasonAppDataAlreadyRemoved'))
    $exception.Data['Code'] = 'AppDataAlreadyRemoved'
    throw $exception
}

function Get-AppDataLocation {
    <#
    .SYNOPSIS
        Die Liste aller Ordner der App: Kind, Path (oder $null) und Problem (Meldung, wenn der Ordner ungültig ist).
    .DESCRIPTION
        Für das Entfernen aufgelöst (-ForRemoval): Ein Ordner, der nicht auf einem lokalen Laufwerk liegt, kommt mit
        Problem AppDataRootInvalid und ohne Pfad. Die Schlüssel in der Anmeldeinformationsverwaltung stehen in Secret.ps1.
    #>
    foreach ($scope in 'Roaming', 'Local') {
        try { [pscustomobject] @{ Kind = $scope; Path = (Get-AppDataRoot -Scope $scope -ForRemoval); Problem = $null } }
        catch {
            if ($_.Exception.Data['Code'] -ne 'AppDataRootInvalid') { throw }
            [pscustomobject] @{ Kind = $scope; Path = $null; Problem = (New-InventoryMessage AppDataRootInvalid $_.Exception.Data['Args']) }
        }
    }
    [pscustomobject] @{ Kind = 'Temp'; Path = (Get-AppTempDirectory); Problem = $null }
    [pscustomobject] @{ Kind = 'Machine'; Path = (Get-AppMachineDirectory); Problem = $null }
}

function Test-AppDataReparsePoint {
    param([System.IO.FileSystemInfo] $Item)
    [bool] ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Get-AppDataTree {
    <#
    .SYNOPSIS
        Alle Einträge unterhalb von Root, Kinder vor ihren Eltern; folgt nie einem Reparse-Point.
    .DESCRIPTION
        Junctions, symbolische Links und Mount-Points kommen als ein Eintrag vor, ihr Ziel wird nicht gelesen.
        Unreadable: Ordner, deren Inhalt sich nicht auflisten ließ.
    #>
    param([Parameter(Mandatory)] [string] $Root)
    $state = @{ Entries = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new(); Unreadable = [System.Collections.Generic.List[string]]::new() }
    Add-AppDataTreeEntry -Directory ([System.IO.DirectoryInfo]::new($Root)) -State $state
    $state
}

function Add-AppDataTreeEntry {
    param([System.IO.DirectoryInfo] $Directory, [hashtable] $State)
    try { $children = @($Directory.EnumerateFileSystemInfos()) }
    catch {
        $State.Unreadable.Add($Directory.FullName)
        return
    }
    foreach ($child in $children) {
        if ($child -is [System.IO.DirectoryInfo] -and -not (Test-AppDataReparsePoint $child)) { Add-AppDataTreeEntry -Directory $child -State $State }
        $State.Entries.Add($child)
    }
}

function Get-AppDataFolderState {
    <#
    .SYNOPSIS
        Zustand eines Ordners für Plan und Entfernen: Missing, Present, RootIsLink oder NotFolder.
    #>
    param([Parameter(Mandatory)] [string] $Path)
    $directory = [System.IO.DirectoryInfo]::new($Path)
    if ($directory.Exists) { if (Test-AppDataReparsePoint $directory) { return 'RootIsLink' } else { return 'Present' } }
    # Ein Link auf ein fehlendes Ziel meldet Exists = $false, hat aber Attribute.
    if ([int] $directory.Attributes -ne -1) { if (Test-AppDataReparsePoint $directory) { return 'RootIsLink' } else { return 'NotFolder' } }
    'Missing'
}

function Get-AppTempFile {
    # Reste der App direkt im Temp-Ordner, nur mit den festen Namen; keine Unterordner, keine Links.
    $directory = [System.IO.DirectoryInfo]::new((Get-AppTempDirectory))
    if (-not $directory.Exists) { return }
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    foreach ($file in $directory.EnumerateFiles()) {
        if (Test-AppDataReparsePoint $file) { continue }
        foreach ($pattern in $script:AppTempFilePatterns) {
            if ([regex]::IsMatch($file.Name, $pattern, $options)) { $file; break }
        }
    }
}

function Get-AppStoredCredential {
    # Dienste mit gespeichertem Schlüssel in der Anmeldeinformationsverwaltung (nie der Schlüssel selbst).
    @($script:SecretVariable.Keys | Sort-Object | Where-Object { Read-StoredSecret -Service $_ })
}

function Measure-AppDataFolder {
    # Größe, Dateien und Links eines Ordners ohne Links zu folgen.
    param([Parameter(Mandatory)] [string] $Path)
    $tree = Get-AppDataTree -Root $Path
    $size = [long] 0; $files = 0; $links = 0
    foreach ($entry in $tree.Entries) {
        if (Test-AppDataReparsePoint $entry) { $links++ }
        elseif ($entry -is [System.IO.FileInfo]) { $files++; $size += $entry.Length }
    }
    @{ Size = $size; FileCount = $files; LinkCount = $links; Unreadable = @($tree.Unreadable) }
}

function Remove-AppDataFolder {
    <#
    .SYNOPSIS
        Löscht einen App-Ordner von unten nach oben, ohne einem Link zu folgen; Ergebnis als Eintrag.
    .DESCRIPTION
        Links (Junction, Symlink) werden als Link entfernt, ihr Ziel bleibt. Ist der Ordner selbst ein Link oder keine
        Ordner, bleibt alles stehen (AppDataRootIsLink, AppDataRootNotFolder). Einträge außerhalb des Ordners kommen beim
        Durchlaufen nicht vor; falls doch, werden sie übersprungen (AppDataOutsideSkipped). Gesperrte Dateien werden
        übersprungen und gezählt, der Rest wird trotzdem entfernt.
        Nur ohne Erhöhung geeignet: Zwischen Auflisten und Löschen könnte ein Prozess desselben Benutzers einen Unterordner
        gegen eine Junction tauschen; gelöscht würde dann nur, was dieser Benutzer ohnehin löschen darf. Ein erhöhtes
        Entfernen (Admin-Ordner, 8c-2) braucht ein eigenes Verfahren (je Ordner prüfen und sofort löschen bzw. Handles).
    #>
    param([Parameter(Mandatory)] [string] $Kind, [Parameter(Mandatory)] [string] $Path)
    $item = New-AppDataRemovalItem -Kind $Kind -Path $Path
    switch (Get-AppDataFolderState -Path $Path) {
        'Missing' { return (Complete-AppDataRemovalItem $item 'NotPresent') }
        'RootIsLink' { $item.Problems.Add((New-InventoryMessage AppDataRootIsLink $Path)); return (Complete-AppDataRemovalItem $item 'Skipped') }
        'NotFolder' { $item.Problems.Add((New-InventoryMessage AppDataRootNotFolder $Path)); return (Complete-AppDataRemovalItem $item 'Skipped') }
    }
    $prefix = $Path.TrimEnd('\') + '\'
    $tree = Get-AppDataTree -Root $Path
    foreach ($folder in $tree.Unreadable) { $item.Problems.Add((New-InventoryMessage AppDataUnreadable $folder)) }
    foreach ($entry in $tree.Entries) {
        if (-not $entry.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $item.Problems.Add((New-InventoryMessage AppDataOutsideSkipped $entry.FullName))
            $item.FailedCount++
            continue
        }
        if (Remove-AppDataEntry -Entry $entry) { $item.RemovedCount++ }
        else {
            $item.FailedCount++
            if (-not $item.FirstFailedPath) { $item.FirstFailedPath = $entry.FullName }
        }
    }
    if (Remove-AppDataEntry -Entry ([System.IO.DirectoryInfo]::new($Path))) { $item.RemovedCount++ }
    elseif (-not $item.FirstFailedPath) { $item.FailedCount++; $item.FirstFailedPath = $Path }
    $result = if ($item.FailedCount -gt 0 -or $item.Problems.Count -gt 0) { 'PartlyRemoved' } else { 'Removed' }
    Complete-AppDataRemovalItem $item $result
}

function Remove-AppDataEntry {
    <#
    .SYNOPSIS
        Löscht genau einen Eintrag: Datei, leeren Ordner oder Link (nie dessen Ziel); $true bei Erfolg.
    .DESCRIPTION
        Ordner nur ohne -Recurse (DirectoryInfo.Delete() ohne Argument): Bei einer Junction entfernt Windows dabei nur
        den Link. Schreibgeschützte Dateien werden vorher beschreibbar gemacht, Links nie (das könnte ihr Ziel ändern).
    #>
    param([Parameter(Mandatory)] [System.IO.FileSystemInfo] $Entry)
    try {
        if ($Entry -is [System.IO.FileInfo] -and -not (Test-AppDataReparsePoint $Entry) -and ($Entry.Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
            $Entry.Attributes = $Entry.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
        }
        $Entry.Delete()
        $true
    }
    catch {
        Write-Verbose "Nicht gelöscht: $($Entry.FullName) ($($_.Exception.Message))"
        $false
    }
}

function New-AppDataRemovalItem {
    param([string] $Kind, [string] $Path)
    [pscustomobject] @{
        PSTypeName      = 'SoftwareInventory.AppDataRemovalItem'
        Kind            = $Kind
        Path            = $Path
        Result          = $null
        RemovedCount    = 0
        FailedCount     = 0
        FirstFailedPath = $null
        Message         = $null
        Problems        = [System.Collections.Generic.List[object]]::new()
    }
}

function Complete-AppDataRemovalItem {
    # Ergebnis setzen und die passende Meldung erzeugen; Problems wird zur festen Liste.
    param($Item, [ValidateSet('Removed', 'NotPresent', 'PartlyRemoved', 'Skipped')] [string] $Result)
    $Item.Result = $Result
    $Item.Message = switch ($Result) {
        'Removed' { New-InventoryMessage AppDataRemoved $Item.Path, $Item.RemovedCount }
        'NotPresent' { New-InventoryMessage AppDataNotPresent $Item.Path }
        'PartlyRemoved' { New-InventoryMessage AppDataPartlyRemoved $Item.Path, $Item.FailedCount }
        'Skipped' { New-InventoryMessage AppDataSkipped $Item.Path }
    }
    $Item.Problems = @($Item.Problems)
    $Item
}

function Get-AppMachineRemovalCommand {
    <#
    .SYNOPSIS
        Argumente für cmd.exe, das den Admin-Teil erhöht entfernt; $null, wenn ein Pfad Zeichen enthält, die cmd deutet.
    .DESCRIPTION
        /d: keine AutoRun-Befehle aus der Registry; /v:off: keine verzögerte Erweiterung, auch wenn sie in der Registry
        eingeschaltet ist. rd /s /q entfernt Junctions im Ordner als Link, ohne ihnen zu folgen (Sandbox-Prüfung
        tests/Sandbox/Test-RdJunction.ps1). Zuletzt rd ohne /s auf den Ordner selbst: scheitert still, wenn noch etwas
        darin liegt. Läuft auch unter Windows PowerShell 5.1 (die Sandbox-Prüfung lädt nur diese Datei).
    #>
    param([Parameter(Mandatory)] [string] $Root)
    $paths = @($script:AppMachineSubfolders | ForEach-Object { [System.IO.Path]::Combine($Root, $_) })
    foreach ($path in @($paths) + $Root) { if ($path -match $script:CmdUnsafePathPattern) { return $null } }
    $commands = @($paths | ForEach-Object { 'rd /s /q "{0}"' -f $_ }) + ('rd "{0}"' -f $Root)
    '/d /v:off /c ' + ($commands -join ' & ')
}

function Remove-AppMachineData {
    <#
    .SYNOPSIS
        Entfernt Helfer-Kopie und HKLM-Sicherungen (Program Files\Softwareverwaltung) mit einer UAC-Abfrage.
    .DESCRIPTION
        Vorher ohne Adminrechte geprüft: Ist der Ordner oder einer der Unterordner ein Link, oder enthält der Pfad Zeichen,
        die cmd deutet, gibt es keine UAC-Abfrage (AppDataRootIsLink, AppDataRootInvalid). Ohne Unterordner ebenfalls nicht
        (NotPresent). Das Ergebnis prüft das Modul danach selbst. Abgelehnt: AppDataMachineDenied, der Rest geht weiter.
    #>
    $root = Get-AppMachineDirectory
    $item = New-AppDataRemovalItem -Kind 'Machine' -Path $root
    $state = Get-AppDataFolderState -Path $root
    if ($state -eq 'Missing') { return (Complete-AppDataRemovalItem $item 'NotPresent') }
    if ($state -ne 'Present') {
        $code = if ($state -eq 'RootIsLink') { 'AppDataRootIsLink' } else { 'AppDataRootNotFolder' }
        $item.Problems.Add((New-InventoryMessage $code $root))
        return (Complete-AppDataRemovalItem $item 'Skipped')
    }
    $present = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $script:AppMachineSubfolders) {
        $path = [System.IO.Path]::Combine($root, $name)
        switch (Get-AppDataFolderState -Path $path) {
            'Present' { $present.Add($path) }
            'RootIsLink' { $item.Problems.Add((New-InventoryMessage AppDataRootIsLink $path)) }
            'NotFolder' { $item.Problems.Add((New-InventoryMessage AppDataRootNotFolder $path)) }
        }
    }
    if ($item.Problems.Count) { return (Complete-AppDataRemovalItem $item 'Skipped') }
    if (-not $present.Count) { return (Complete-AppDataRemovalItem $item 'NotPresent') }
    $arguments = Get-AppMachineRemovalCommand -Root $root
    if (-not $arguments) {
        $item.Problems.Add((New-InventoryMessage AppDataRootInvalid 'ProgramFiles', $root))
        return (Complete-AppDataRemovalItem $item 'Skipped')
    }

    $started = $true
    $exit = $null
    try { $exit = Invoke-ElevatedSystemTool -Tool 'cmd.exe' -Arguments $arguments }
    catch {
        if (Test-ElevationCancelled $_) {
            $item.Problems.Add((New-InventoryMessage AppDataMachineDenied $root))
            return (Complete-AppDataRemovalItem $item 'Skipped')
        }
        # Nicht gestartet: Die Ordner sind dann noch da und zählen unten als nicht entfernt.
        $started = $false
        Write-Verbose "Admin-Ordner nicht entfernt: $($_.Exception.Message)"
    }
    if ($started -and $null -eq $exit) { $item.Problems.Add((New-InventoryMessage AppDataMachineTimeout $root)) }
    foreach ($path in $present) {
        if (Test-Path -LiteralPath $path) {
            $item.FailedCount++
            if (-not $item.FirstFailedPath) { $item.FirstFailedPath = $path }
        }
        else { $item.RemovedCount++ }
    }
    $result = if ($item.FailedCount -or $item.Problems.Count) { 'PartlyRemoved' } else { 'Removed' }
    Complete-AppDataRemovalItem $item $result
}

function Remove-AppStoredCredential {
    # Gespeicherte Schlüssel der App; Umgebungsvariablen bleiben (die hat der Benutzer selbst gesetzt).
    $item = New-AppDataRemovalItem -Kind 'Credentials' -Path "$script:CredentialPrefix/*"
    $removed = [System.Collections.Generic.List[string]]::new()
    # Jeden Dienst direkt löschen statt erst zu lesen: So fallen auch leere oder unlesbare Einträge weg.
    foreach ($service in $script:SecretVariable.Keys | Sort-Object) {
        switch (Remove-StoredSecret -Service $service) {
            'Removed' { $removed.Add($service); $item.RemovedCount++ }
            'Failed' {
                $item.FailedCount++
                $item.Problems.Add((New-InventoryMessage AppDataCredentialFailed $service))
            }
        }
    }
    $result = if ($item.FailedCount) { 'PartlyRemoved' } elseif ($removed.Count) { 'Removed' } else { 'NotPresent' }
    $item = Complete-AppDataRemovalItem $item $result
    if ($removed.Count) { $item.Message = New-InventoryMessage AppDataCredentialRemoved ($removed -join ', ') }
    $item
}

function Remove-AppTempFile {
    # Reste der App im Temp-Ordner (nur die festen Namen aus $script:AppTempFilePatterns).
    $item = New-AppDataRemovalItem -Kind 'Temp' -Path (Get-AppTempDirectory)
    foreach ($file in @(Get-AppTempFile)) {
        if (Remove-AppDataEntry -Entry $file) { $item.RemovedCount++ }
        else {
            $item.FailedCount++
            if (-not $item.FirstFailedPath) { $item.FirstFailedPath = $file.FullName }
        }
    }
    $result = if ($item.FailedCount) { 'PartlyRemoved' } elseif ($item.RemovedCount) { 'Removed' } else { 'NotPresent' }
    $item = Complete-AppDataRemovalItem $item $result
    if ($result -eq 'Removed') { $item.Message = New-InventoryMessage AppDataTempRemoved $item.RemovedCount, $item.Path }
    $item
}
