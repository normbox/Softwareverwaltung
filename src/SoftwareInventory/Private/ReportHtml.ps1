# HTML-Bericht: eine eigenständige Datei ohne externe Ressourcen (offline lesbar, weitergebbar).

$script:RatingLabel = @{ Red = 'Rot'; Yellow = 'Gelb'; Green = 'Grün'; Gray = 'Grau' }
$script:AssessmentLabel = @{ Affected = 'betroffen'; PossiblyAffected = 'möglicherweise betroffen'; Informational = 'Hinweis' }

function Protect-ReportText {
    # Persönliche Angaben und Schlüssel ersetzen (gemeinsame Regel, siehe PrivateData.ps1).
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    Protect-PrivateText $Text
}

function ConvertTo-HtmlText {
    param($Value)
    [System.Net.WebUtility]::HtmlEncode((Protect-ReportText ([string] $Value)))
}

function ConvertTo-SecurityReportHtml {
    param([object[]] $Rating, $Setting, [datetime] $GeneratedAt = (Get-Date))

    $e = { param($v) ConvertTo-HtmlText $v }
    $count = @{}
    foreach ($key in 'Red', 'Yellow', 'Green', 'Gray') { $count[$key] = @($Rating | Where-Object Rating -eq $key).Count }
    $services = @(Get-EnabledName $Setting.Services)
    $servicesText = if ($services) { $services -join ', ' } else { 'keine' }

    $rows = foreach ($r in $Rating) {
        $u = $r.UpdateStatus
        $v = $r.VulnerabilityStatus
        $vulns = @(if ($v) { $v.Vulnerabilities }) | Where-Object { $_ }
        $relevant = @($vulns | Where-Object Assessment -ne 'Informational')
        $info = @($vulns | Where-Object Assessment -eq 'Informational')
        $hasUpdate = [bool] ($u -and $u.Status -eq 'Outdated')

        $latest = if ($u -and $u.LatestVersion) {
            (& $e $u.LatestVersion) + " <span class='muted'>(" + (& $e $u.Source) + ')</span>' +
            $(if (-not $u.Confirmed) { " <span class='tag'>unbestätigt</span>" })
        } else { "<span class='muted'>–</span>" }
        $reasons = ($r.Reasons | ForEach-Object { '<li>' + (& $e (ConvertTo-MessageText $_)) + '</li>' }) -join ''

        $vulnRows = foreach ($x in $relevant + $info) {
            $epss = if ($null -ne $x.Epss) { '{0:N1} %' -f ($x.Epss * 100) } else { '–' }
            $score = if ($null -ne $x.Score) { "$($x.Score)" } else { '–' }
            $kev = if ($x.Kev) { "<span class='tag kev'>KEV</span>" } else { '' }
            $published = if ($x.Published) { ([string] $x.Published).Substring(0, [Math]::Min(10, ([string] $x.Published).Length)) } else { '–' }
            "<tr class='$(if ($x.Assessment -eq 'Informational') { 'info' })'><td><a href='$(& $e $x.Url)'>$(& $e $x.CveId)</a> $kev</td>" +
            "<td>$(& $e $script:AssessmentLabel[$x.Assessment])</td><td>$score</td><td>$epss</td><td>$published</td>" +
            "<td>$(& $e (ConvertTo-MessageText $x.Note)) <span class='muted'>$(& $e $x.Description)</span></td></tr>"
        }
        $location = $r.Record.FilePath
        if (-not $location) { $location = $r.Record.InstallLocation }
        $details = @(
            "<p><b>Quelle:</b> $(& $e ($r.Record.Sources -join ', '))" + $(if ($location) { " · <b>Ort:</b> $(& $e $location)" }) + '</p>'
            if ($v -and $v.Cpe) { "<p><b>CPE:</b> $(& $e ($v.Cpe -join ', '))" + $(if ($v.CpeSource -eq 'User') { ' (vom Benutzer bestätigt)' }) + '</p>' }
            if ($v -and $v.Notes) { "<p class='muted'>$(& $e (ConvertTo-MessageText @($v.Notes)))</p>" }
            if ($vulnRows) {
                "<table class='cves'><thead><tr><th>CVE</th><th>Bewertung</th><th>CVSS</th><th>EPSS</th><th>Veröffentlicht</th><th>Hinweis</th></tr></thead><tbody>$($vulnRows -join '')</tbody></table>"
            }
        ) -join ''

        "<tr class='row' data-rating='$($r.Rating)' data-update='$($hasUpdate.ToString().ToLower())' data-risk='$(([bool] $relevant).ToString().ToLower())'>" +
        "<td><span class='badge $($r.Rating.ToLower())'>$($script:RatingLabel[$r.Rating])</span></td>" +
        "<td><details><summary>$(& $e $r.Name)</summary>$details</details></td>" +
        "<td>$(& $e $r.Version)</td><td>$latest</td><td><ul>$reasons</ul></td></tr>"
    }

    $generated = $GeneratedAt.ToString('dd.MM.yyyy HH:mm', [cultureinfo]::GetCultureInfo('de-DE'))
    @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Softwareverwaltung – Sicherheitsbericht</title>
<style>
:root { --bg:#fff; --fg:#1b1b1b; --muted:#666; --line:#ddd; --head:#f4f4f4; --red:#c62828; --yellow:#b58100; --green:#2e7d32; --gray:#757575; --link:#0b57d0; }
@media (prefers-color-scheme: dark) { :root { --bg:#141414; --fg:#e8e8e8; --muted:#9a9a9a; --line:#333; --head:#1f1f1f; --red:#ef5350; --yellow:#fbc02d; --green:#66bb6a; --gray:#9e9e9e; --link:#8ab4f8; } }
body { background:var(--bg); color:var(--fg); font:14px/1.45 "Segoe UI", system-ui, sans-serif; margin:0; padding:16px; }
h1 { font-size:20px; margin:0 0 4px; } .muted { color:var(--muted); } a { color:var(--link); }
.summary { display:flex; flex-wrap:wrap; gap:8px; margin:12px 0; }
.summary span, button { border:1px solid var(--line); border-radius:6px; padding:4px 10px; background:var(--head); color:var(--fg); font:inherit; }
button { cursor:pointer; } button.active { outline:2px solid var(--link); }
table { border-collapse:collapse; width:100%; } th, td { text-align:left; vertical-align:top; padding:6px 8px; border-bottom:1px solid var(--line); }
th { background:var(--head); } ul { margin:0; padding-left:18px; } summary { cursor:pointer; font-weight:600; }
.badge { display:inline-block; min-width:44px; text-align:center; border-radius:10px; padding:1px 8px; color:#fff; font-weight:600; }
.badge.red { background:var(--red); } .badge.yellow { background:var(--yellow); color:#000; } .badge.green { background:var(--green); } .badge.gray { background:var(--gray); }
.tag { border:1px solid var(--line); border-radius:4px; padding:0 4px; font-size:12px; } .tag.kev { border-color:var(--red); color:var(--red); font-weight:600; }
table.cves { margin-top:6px; font-size:13px; } tr.info { opacity:.7; }
.wrap { overflow-x:auto; }
</style>
</head>
<body>
<h1>Sicherheitsbericht</h1>
<div class="muted">Erstellt am $generated · $($Rating.Count) Programme · Aktivierte Dienste: $(& $e $servicesText)</div>
<div class="summary">
<span><span class="badge red">Rot</span> $($count.Red)</span><span><span class="badge yellow">Gelb</span> $($count.Yellow)</span>
<span><span class="badge gray">Grau</span> $($count.Gray)</span><span><span class="badge green">Grün</span> $($count.Green)</span>
</div>
<div class="summary" id="filters">
<button data-filter="all" class="active">Alle</button><button data-filter="update">Updates verfügbar</button><button data-filter="risk">Sicherheitsrisiko</button>
<button data-filter="Red">Rot</button><button data-filter="Yellow">Gelb</button><button data-filter="Gray">Grau</button><button data-filter="Green">Grün</button>
</div>
<div class="wrap"><table>
<thead><tr><th>Ampel</th><th>Programm</th><th>Installiert</th><th>Neueste</th><th>Gründe</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody></table></div>
<p class="muted">Rot: aktiv ausgenutzte (CISA KEV) oder kritische Lücke (CVSS ab 9). Gelb: andere Lücken, „möglicherweise betroffen“ oder Update verfügbar. Grün: geprüft ohne Befund. Grau: nicht auf Lücken geprüft (Grund in der Zeile).
Quellen: NVD, CISA KEV, FIRST EPSS, winget, GitHub. Unbestätigte Angaben sind gekennzeichnet. Angaben ohne Gewähr.</p>
<script>
document.getElementById('filters').addEventListener('click', function (ev) {
  var f = ev.target.getAttribute('data-filter'); if (!f) return;
  document.querySelectorAll('#filters button').forEach(function (b) { b.classList.toggle('active', b === ev.target); });
  document.querySelectorAll('tr.row').forEach(function (row) {
    var show = f === 'all' || (f === 'update' && row.dataset.update === 'true') || (f === 'risk' && row.dataset.risk === 'true') || row.dataset.rating === f;
    row.style.display = show ? '' : 'none';
  });
});
</script>
</body>
</html>
"@
}
