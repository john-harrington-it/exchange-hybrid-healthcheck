function ConvertTo-EhcHtmlDashboard {
    <#
    .SYNOPSIS
        Renders health check results as a self-contained HTML dashboard.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result,

        [string]$Title = 'Exchange Hybrid Health Check'
    )

    $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }
    $rank = @{ Fail = 0; Warning = 1; Info = 2; Skipped = 3; Pass = 4 }
    $count = @{}
    foreach ($s in $rank.Keys) { $count[$s] = @($Result | Where-Object { $_.Status -eq $s }).Count }

    $overall = 'Pass'
    if ($count['Fail'] -gt 0) { $overall = 'Fail' }
    elseif ($count['Warning'] -gt 0) { $overall = 'Warning' }
    $overallText = @{ Pass = 'Healthy'; Warning = 'Needs attention'; Fail = 'Action required' }[$overall]

    $sb = New-Object -TypeName System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine(('<title>{0}</title>' -f (& $enc $Title)))
    [void]$sb.AppendLine(@'
<style>
:root{--bg:#0b1220;--panel:#111a2e;--line:#22304d;--text:#e2e8f0;--muted:#94a3b8;--Pass:#22c55e;--Warning:#f59e0b;--Fail:#ef4444;--Info:#38bdf8;--Skipped:#64748b}
*{box-sizing:border-box}body{margin:0;font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;background:var(--bg);color:var(--text)}
header{display:flex;flex-wrap:wrap;gap:16px;align-items:center;justify-content:space-between;padding:26px 32px;border-bottom:1px solid var(--line)}
h1{margin:0;font-size:22px}.meta{color:var(--muted);font-size:13px}
.pill{display:inline-block;padding:3px 10px;border-radius:999px;font-weight:600;font-size:12px;color:#0b1220}
.big{font-size:16px;padding:8px 16px}
.Pass{background:var(--Pass)}.Warning{background:var(--Warning)}.Fail{background:var(--Fail)}.Info{background:var(--Info)}.Skipped{background:var(--Skipped);color:#e2e8f0}
main{padding:24px 32px;max-width:1400px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:22px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px;cursor:pointer}
.card .n{font-size:28px;font-weight:700}.card .l{color:var(--muted)}
.cats{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-bottom:22px}
.cat{background:var(--panel);border:1px solid var(--line);border-left:5px solid var(--Skipped);border-radius:10px;padding:12px 14px}
.cat.Pass{border-left-color:var(--Pass)}.cat.Warning{border-left-color:var(--Warning)}.cat.Fail{border-left-color:var(--Fail)}.cat.Info{border-left-color:var(--Info)}
.cat{background:var(--panel);color:var(--text)}.cat b{display:block}.cat span{color:var(--muted);font-size:12px}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px;overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--Info);font-weight:600}td.d{color:#cbd5e1;min-width:320px}
footer{color:var(--muted);font-size:12px;padding:6px 32px 28px}
</style></head><body>
'@)
    [void]$sb.AppendLine(('<header><div><h1>{0}</h1><div class="meta">Generated {1} from {2}. Read-only checks; no configuration was changed.</div></div>' -f (& $enc $Title), (Get-Date -Format 'yyyy-MM-dd HH:mm'), (& $enc ([Environment]::MachineName))))
    [void]$sb.AppendLine(('<span class="pill big {0}">Overall: {1}</span></header><main>' -f $overall, $overallText))

    [void]$sb.AppendLine('<div class="grid">')
    foreach ($s in @('Fail', 'Warning', 'Pass', 'Info', 'Skipped')) {
        [void]$sb.AppendLine(('<div class="card" data-filter="{0}"><div class="n">{1}</div><div class="l"><span class="pill {0}">{0}</span></div></div>' -f $s, $count[$s]))
    }
    [void]$sb.AppendLine('</div><div class="cats">')
    foreach ($group in ($Result | Group-Object -Property Category | Sort-Object -Property Name)) {
        $worst = ($group.Group | Sort-Object -Property { $rank[$_.Status] } | Select-Object -First 1).Status
        $issues = @($group.Group | Where-Object { $_.Status -in @('Fail', 'Warning') }).Count
        [void]$sb.AppendLine(('<div class="cat {0}"><b>{1}</b><span>{2} check(s), {3} issue(s)</span></div>' -f $worst, (& $enc $group.Name), $group.Count, $issues))
    }
    [void]$sb.AppendLine('</div><section><table><thead><tr><th>Status</th><th>Category</th><th>Check</th><th>Target</th><th>Detail</th></tr></thead><tbody>')
    foreach ($r in ($Result | Sort-Object -Property { $rank[$_.Status] }, Category, Check)) {
        [void]$sb.AppendLine(('<tr data-status="{0}"><td><span class="pill {0}">{0}</span></td><td>{1}</td><td>{2}</td><td>{3}</td><td class="d">{4}</td></tr>' -f $r.Status, (& $enc $r.Category), (& $enc $r.Check), (& $enc $r.Target), (& $enc $r.Detail)))
    }
    [void]$sb.AppendLine('</tbody></table></section></main>')
    [void]$sb.AppendLine('<footer>Exchange Hybrid Health Check. Click a status card to filter; click again to clear.</footer>')
    [void]$sb.AppendLine('<script>document.querySelectorAll(".card").forEach(function(c){c.addEventListener("click",function(){var f=c.dataset.filter,on=c.classList.toggle("on");document.querySelectorAll(".card").forEach(function(o){if(o!==c)o.classList.remove("on")});document.querySelectorAll("tbody tr").forEach(function(r){r.style.display=(!on||r.dataset.status===f)?"":"none"})})})</script>')
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}
