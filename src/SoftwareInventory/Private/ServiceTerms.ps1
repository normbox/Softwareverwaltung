# Nutzungsbedingungen externer Dienste (Stand 26.10.2026). Maßgeblich sind die verlinkten Originale.
# Die Angaben sind reine Information: Sie schalten nichts ein oder aus. Die Texte stehen in
# SoftwareInventory.Strings.psd1 (ServiceTerms<Dienst>Name/Terms/Company, ServiceTermsGeneral<Nutzung>).

$script:ServiceTerms = @(
    [ordered]@{ Service = 'WingetSearch'; CompanyHint = $true; Url = 'https://learn.microsoft.com/windows/package-manager/' }
    [ordered]@{ Service = 'GitHub'; CompanyHint = $true; Url = 'https://docs.github.com/site-policy/github-terms/github-terms-of-service' }
    [ordered]@{ Service = 'NVD'; CompanyHint = $false; Url = 'https://nvd.nist.gov/developers/terms-of-use' }
    [ordered]@{ Service = 'CIRCL'; CompanyHint = $false; Url = 'https://vulnerability.circl.lu/about' }
    [ordered]@{ Service = 'KEV'; CompanyHint = $false; Url = 'https://www.cisa.gov/known-exploited-vulnerabilities-catalog' }
    [ordered]@{ Service = 'EPSS'; CompanyHint = $false; Url = 'https://www.first.org/epss/faq' }
)
