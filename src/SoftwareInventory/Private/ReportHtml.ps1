# HTML-Bericht: eine eigenständige Datei ohne externe Ressourcen (offline lesbar, weitergebbar).
# Texte aus SoftwareInventory.Strings.psd1 (Report…), Datum und Zahlen in der Sprache der Oberfläche.

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
    # Feste Texte des Berichts, maskiert (& < > " ') – auch spätere Übersetzungen enthalten so kein HTML.
    $t = { param([string] $Key, [object[]] $Arguments = @()) [System.Security.SecurityElement]::Escape((Get-LocalizedString "Report$Key" $Arguments)) }
    $count = @{}
    foreach ($key in 'Red', 'Yellow', 'Green', 'Gray') { $count[$key] = @($Rating | Where-Object Rating -eq $key).Count }
    $services = @(Get-EnabledName $Setting.Services)
    $servicesText = if ($services) { $services -join ', ' } else { Get-LocalizedString 'ReportNoServices' }

    $rows = foreach ($r in $Rating) {
        $u = $r.UpdateStatus
        $v = $r.VulnerabilityStatus
        $vulns = @(if ($v) { $v.Vulnerabilities }) | Where-Object { $_ }
        $relevant = @($vulns | Where-Object Assessment -ne 'Informational')
        $info = @($vulns | Where-Object Assessment -eq 'Informational')
        $hasUpdate = [bool] ($u -and $u.Status -eq 'Outdated')

        $latest = if ($u -and $u.LatestVersion) {
            (& $e $u.LatestVersion) + " <span class='muted'>(" + (& $e $u.Source) + ')</span>' +
            $(if (-not $u.Confirmed) { " <span class='tag'>$(& $t Unconfirmed)</span>" })
        } else { "<span class='muted'>–</span>" }
        $reasons = ($r.Reasons | ForEach-Object { '<li>' + (& $e (ConvertTo-MessageText $_)) + '</li>' }) -join ''

        $vulnRows = foreach ($x in $relevant + $info) {
            $epss = if ($null -ne $x.Epss) { '{0:N1} %' -f ($x.Epss * 100) } else { '–' }
            $score = if ($null -ne $x.Score) { "$($x.Score)" } else { '–' }
            $kev = if ($x.Kev) { "<span class='tag kev'>KEV</span>" } else { '' }
            $published = if ($x.Published) { ([string] $x.Published).Substring(0, [Math]::Min(10, ([string] $x.Published).Length)) } else { '–' }
            # Angabe jeder Quelle mit Namensnennung (CC BY 4.0 bei CIRCL)
            $sources = @(if ($x.PSObject.Properties['Sources']) { $x.Sources }) | Where-Object { $_ } | ForEach-Object {
                $line = (& $t "Verdict$($_.Verdict)") + $(if ($_.Range) { " ($(& $e $_.Range))" })
                "<br><span class='muted'>$(& $e $_.Source): $line · $(& $e (ConvertTo-MessageText $_.Attribution))</span>"
            }
            "<tr class='$(if ($x.Assessment -eq 'Informational') { 'info' })'><td><a href='$(& $e $x.Url)'>$(& $e $x.CveId)</a> $kev</td>" +
            "<td>$(& $t "Assessment$($x.Assessment)")</td><td>$score</td><td>$epss</td><td>$published</td>" +
            "<td>$(& $e (ConvertTo-MessageText $x.Note)) <span class='muted'>$(& $e $x.Description)</span>$($sources -join '')</td></tr>"
        }
        $location = $r.Record.FilePath
        if (-not $location) { $location = $r.Record.InstallLocation }
        $details = @(
            "<p><b>$(& $t SourceLabel)</b> $(& $e ($r.Record.Sources -join ', '))" + $(if ($location) { " · <b>$(& $t LocationLabel)</b> $(& $e $location)" }) + '</p>'
            if ($v -and $v.Cpe) { "<p><b>CPE:</b> $(& $e ($v.Cpe -join ', '))" + $(if ($v.CpeSource -eq 'User') { " $(& $t CpeUserConfirmed)" }) + '</p>' }
            if ($v -and $v.Notes) { "<p class='muted'>$(& $e (ConvertTo-MessageText @($v.Notes)))</p>" }
            if ($vulnRows) {
                "<table class='cves'><thead><tr><th>CVE</th><th>$(& $t ColumnAssessment)</th><th>CVSS</th><th>EPSS</th><th>$(& $t ColumnPublished)</th><th>$(& $t ColumnNote)</th></tr></thead><tbody>$($vulnRows -join '')</tbody></table>"
            }
        ) -join ''

        "<tr class='row' data-rating='$($r.Rating)' data-update='$($hasUpdate.ToString().ToLower())' data-risk='$(([bool] $relevant).ToString().ToLower())'>" +
        "<td><span class='badge $($r.Rating.ToLower())'>$(& $t "Rating$($r.Rating)")</span></td>" +
        "<td><details><summary>$(& $e $r.Name)</summary>$details</details></td>" +
        "<td>$(& $e $r.Version)</td><td>$latest</td><td><ul>$reasons</ul></td></tr>"
    }

    $generated = $GeneratedAt.ToString('g', [cultureinfo]::CurrentCulture)
    $language = [cultureinfo]::CurrentUICulture.TwoLetterISOLanguageName
    @"
<!DOCTYPE html>
<html lang="$language">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(& $t Title)</title>
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
<h1>$(& $t Heading)</h1>
<div class="muted">$(& $t Meta $generated, $Rating.Count, (Protect-ReportText $servicesText))</div>
<div class="summary">
<span><span class="badge red">$(& $t RatingRed)</span> $($count.Red)</span><span><span class="badge yellow">$(& $t RatingYellow)</span> $($count.Yellow)</span>
<span><span class="badge gray">$(& $t RatingGray)</span> $($count.Gray)</span><span><span class="badge green">$(& $t RatingGreen)</span> $($count.Green)</span>
</div>
<div class="summary" id="filters">
<button data-filter="all" class="active">$(& $t FilterAll)</button><button data-filter="update">$(& $t FilterUpdates)</button><button data-filter="risk">$(& $t FilterRisk)</button>
<button data-filter="Red">$(& $t RatingRed)</button><button data-filter="Yellow">$(& $t RatingYellow)</button><button data-filter="Gray">$(& $t RatingGray)</button><button data-filter="Green">$(& $t RatingGreen)</button>
</div>
<div class="wrap"><table>
<thead><tr><th>$(& $t ColumnRating)</th><th>$(& $t ColumnProgram)</th><th>$(& $t ColumnInstalled)</th><th>$(& $t ColumnLatest)</th><th>$(& $t ColumnReasons)</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody></table></div>
<p class="muted">$(& $t Legend)
$(& $t Sources)</p>
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
