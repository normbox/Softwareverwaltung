# Kurzfassung der Nutzungsbedingungen externer Dienste (Stand 26.10.2026). Maßgeblich sind die
# verlinkten Originale. Die Angaben sind reine Information: Sie schalten nichts ein oder aus.

$script:ServiceTerms = @(
    [ordered]@{
        Service = 'WingetSearch'
        Name    = 'winget-Quellen (Microsoft)'
        Terms   = 'Die Suche nutzt die eingerichteten winget-Quellen. Für die Quelle „msstore“ gelten die Bedingungen des Microsoft Store, die winget beim ersten Zugriff anzeigt. Jedes Paket hat außerdem eine eigene Lizenz.'
        Company = 'Viele Programme sind nur privat kostenlos. Prüfen Sie vor dem Installieren oder Aktualisieren in der Firma die Lizenz des Pakets.'
        Url     = 'https://learn.microsoft.com/windows/package-manager/'
    }
    [ordered]@{
        Service = 'GitHub'
        Name    = 'GitHub-API'
        Terms   = 'Es gelten die GitHub-Nutzungsbedingungen. Ohne Token sind 60 Anfragen pro Stunde erlaubt, mit Token 5.000.'
        Company = 'Verwenden Sie in der Firma nur ein Token, das Ihre Richtlinien erlauben, am besten ohne Rechte (nur Lesen öffentlicher Daten).'
        Url     = 'https://docs.github.com/site-policy/github-terms/github-terms-of-service'
    }
    [ordered]@{
        Service = 'NVD'
        Name    = 'National Vulnerability Database (NIST)'
        Terms   = 'Kostenlos, auch kommerziell. Die NVD bittet um den Hinweis: „This product uses the NVD API but is not endorsed or certified by the NVD.“ Ohne API-Schlüssel gelten strengere Abfragegrenzen.'
        Company = $null
        Url     = 'https://nvd.nist.gov/developers/terms-of-use'
    }
    [ordered]@{
        Service = 'KEV'
        Name    = 'Known Exploited Vulnerabilities (CISA)'
        Terms   = 'Gemeinfrei (CC0 1.0), auch kommerziell nutzbar. Logo und Siegel der CISA dürfen nicht verwendet werden.'
        Company = $null
        Url     = 'https://www.cisa.gov/known-exploited-vulnerabilities-catalog'
    }
    [ordered]@{
        Service = 'EPSS'
        Name    = 'Exploit Prediction Scoring System (FIRST)'
        Terms   = 'Kostenlos und ohne Anmeldung. FIRST bittet um eine Quellenangabe, wenn EPSS-Daten in Produkten oder Veröffentlichungen verwendet werden.'
        Company = $null
        Url     = 'https://www.first.org/epss/faq'
    }
)

$script:ServiceTermsGeneral = @{
    Private = 'Alle Dienste sind für die private Nutzung kostenlos. Sie bleiben aus, bis Sie sie unter „Einstellungen“ einzeln einschalten.'
    Company = 'Die Dienste sind auch für Firmen kostenlos. Sie senden Programm-, Hersteller- und Versionsangaben ins Internet. Prüfen Sie deshalb vor dem Einschalten Ihre Richtlinien zu IT-Sicherheit und Datenschutz. Alle Dienste bleiben aus, bis Sie sie unter „Einstellungen“ einzeln einschalten.'
}
