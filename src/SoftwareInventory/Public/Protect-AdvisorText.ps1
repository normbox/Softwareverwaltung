function Protect-AdvisorText {
    <#
    .SYNOPSIS
        Bereinigt einen Text, bevor die App ihn an ein Modell schickt.
    .DESCRIPTION
        Dieselbe Regel wie für die Tool-Antworten (Protect-PrivateText): eigenes Profil, Profile anderer
        Benutzer, Benutzername, Rechnername, Domäne und gespeicherte API-Schlüssel werden ersetzt.
        Die App nutzt das für die Fragen des Benutzers.
    .EXAMPLE
        Protect-AdvisorText -Text 'Was liegt in C:\Users\max\Downloads?'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Text
    )
    process { Protect-PrivateText $Text }
}
