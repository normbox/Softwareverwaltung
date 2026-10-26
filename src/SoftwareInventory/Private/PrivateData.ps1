# Bereinigung persönlicher Daten, bevor Text den Rechner verlässt oder weitergegeben wird
# (HTML-Bericht, KI-Berater). Ersetzt werden Benutzerpfade, Benutzername, Rechnername und
# Domäne; API-Schlüssel entfernt Protect-SecretText. Gilt immer, auch für lokale Modelle.

function Get-PrivateIdentity {
    # Werte, die ersetzt werden; eigene Funktion, damit Tests sie vorgeben können.
    [pscustomobject] @{
        UserProfile  = $env:USERPROFILE
        UserName     = $env:USERNAME
        ComputerName = $env:COMPUTERNAME
        Domain       = $env:USERDOMAIN
    }
}

function Protect-PrivateText {
    <#
    .SYNOPSIS
        Ersetzt persönliche Angaben in einem Text durch Platzhalter.
    .DESCRIPTION
        - Eigenes Profil (C:\Users\<Name>) → %USERPROFILE%, auch in JSON mit doppelten Backslashes
          und mit Schrägstrichen.
        - Profile anderer Benutzer → C:\Users\%OTHERUSER% (Public und Default bleiben).
        - Benutzername → %USERNAME%, Rechnername → %COMPUTERNAME%, Domäne → %USERDOMAIN%
          (jeweils nur als ganzes Wort).
        - Bekannte API-Schlüssel → ***.
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    if (-not $Text) { return $Text }
    $id = Get-PrivateIdentity
    $sep = '(?:\\\\|\\|/)'   # \\ (JSON), \ oder /

    if ($id.UserProfile) {
        $parts = $id.UserProfile -split '[\\/]' | Where-Object { $_ }
        $pattern = ($parts | ForEach-Object { [regex]::Escape($_) }) -join $sep
        $Text = [regex]::Replace($Text, "$pattern(?=$sep|\b|$)", '%USERPROFILE%', 'IgnoreCase')
    }
    # Profile anderer Benutzer: Laufwerk:\Users\<Name>
    $Text = [regex]::Replace($Text, "(?<prefix>\b[A-Za-z]:$sep(?:Users|Benutzer)$sep)(?<name>[^\\/""'\s:*?<>|]+)", {
            param($m)
            $name = $m.Groups['name'].Value
            if ($name -in 'Public', 'Default', 'Default User', 'All Users', '%OTHERUSER%', '%USERNAME%') { return $m.Value }
            # Eigener Name auf einem anderen Laufwerk (z. B. Sicherung auf USB): wie der Benutzername behandeln.
            if ($id.UserName -and $name -eq $id.UserName) { return $m.Groups['prefix'].Value + '%USERNAME%' }
            $m.Groups['prefix'].Value + '%OTHERUSER%'
        }, 'IgnoreCase')

    $words = [ordered]@{}
    if ($id.ComputerName) { $words[$id.ComputerName] = '%COMPUTERNAME%' }
    if ($id.Domain -and $id.Domain -ne $id.ComputerName -and $id.Domain -notin 'WORKGROUP', 'NT AUTHORITY', 'BUILTIN') { $words[$id.Domain] = '%USERDOMAIN%' }
    if ($id.UserName -and $id.UserName.Length -ge 2) { $words[$id.UserName] = '%USERNAME%' }
    foreach ($word in $words.Keys) {
        $Text = [regex]::Replace($Text, "(?<![\w%])$([regex]::Escape($word))(?![\w%])", $words[$word], 'IgnoreCase')
    }
    Protect-SecretText $Text
}
