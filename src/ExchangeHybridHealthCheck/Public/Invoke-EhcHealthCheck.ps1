function Invoke-EhcHealthCheck {
    <#
    .SYNOPSIS
        Runs the full Exchange hybrid health check and writes an HTML dashboard, CSV, and JSON.

    .DESCRIPTION
        Runs the selected read-only checks and returns all results. Unless -NoReport is set,
        writes to -OutputPath:

          index.html    Dashboard
          results.csv   Flat results for Excel or ticketing
          results.json  Results for automation or trend tracking
          run.log       Log of the run

        Run from the Exchange Management Shell on a 2016/2019 server or a management host, and
        connect to Exchange Online with a prefix so cmdlet names do not collide:

          Connect-ExchangeOnline -Prefix Cloud

        Any check whose cmdlets are unavailable returns 'Skipped', so the tool also works
        on-premises-only or cloud-only. One check failing never stops the others.

    .PARAMETER Check
        Checks to run. Default: all.

    .PARAMETER Server
        Exchange servers to check. Defaults to all Exchange 2016/2019 mailbox servers.

    .PARAMETER CloudPrefix
        Prefix used with Connect-ExchangeOnline -Prefix. Default 'Cloud'.

    .PARAMETER OutputPath
        Report folder. Defaults to .\EhcReport-<timestamp>.

    .PARAMETER CertificateWarningDays
        Days before certificate expiry that produce a Warning. Default 30.

    .PARAMETER NoReport
        Return results only; do not write files.

    .EXAMPLE
        Invoke-EhcHealthCheck -OutputPath C:\Reports\Exchange

    .EXAMPLE
        Invoke-EhcHealthCheck -Check Certificate, TransportQueue -NoReport | Where-Object Status -ne 'Pass'

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidateSet('Certificate', 'HybridConfiguration', 'Connector', 'MigrationBatch', 'TransportQueue', 'Database', 'Service')]
        [string[]]$Check = @('Certificate', 'HybridConfiguration', 'Connector', 'MigrationBatch', 'TransportQueue', 'Database', 'Service'),

        [ValidateNotNullOrEmpty()]
        [string[]]$Server,

        [ValidatePattern('^[A-Za-z]*$')]
        [string]$CloudPrefix = 'Cloud',

        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path (Get-Location).Path -ChildPath ('EhcReport-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmm'))),

        [ValidateRange(1, 365)]
        [int]$CertificateWarningDays = 30,

        [switch]$NoReport
    )

    if (-not $NoReport) {
        if (-not (Test-Path -Path $OutputPath)) {
            $null = New-Item -Path $OutputPath -ItemType Directory -Force -WhatIf:$false -Confirm:$false
        }
        $script:EhcLogPath = Join-Path -Path $OutputPath -ChildPath 'run.log'
    }
    Write-EhcLog -Message ('Health check started. Checks: {0}' -f ($Check -join ', '))

    $serverArg = @{}
    if ($Server) { $serverArg['Server'] = $Server }
    $categoryName = @{
        Certificate         = 'Certificates'
        HybridConfiguration = 'Hybrid configuration'
        Connector           = 'Mail flow connectors'
        MigrationBatch      = 'Migration batches'
        TransportQueue      = 'Transport queues'
        Database            = 'Databases and DAG'
        Service             = 'Services'
    }
    $order = @('Certificate', 'HybridConfiguration', 'Connector', 'MigrationBatch', 'TransportQueue', 'Database', 'Service')

    $results = New-Object -TypeName System.Collections.Generic.List[object]
    foreach ($key in ($order | Where-Object { $_ -in $Check })) {
        try {
            $output = switch ($key) {
                'Certificate' { Test-EhcCertificate @serverArg -WarningDays $CertificateWarningDays }
                'HybridConfiguration' { Test-EhcHybridConfiguration -CloudPrefix $CloudPrefix -WarningDays $CertificateWarningDays }
                'Connector' { Test-EhcConnector -CloudPrefix $CloudPrefix }
                'MigrationBatch' { Test-EhcMigrationBatch -CloudPrefix $CloudPrefix -IncludeFailedUser }
                'TransportQueue' { Test-EhcTransportQueue @serverArg }
                'Database' { Test-EhcDatabaseHealth @serverArg }
                'Service' { Test-EhcServiceHealth @serverArg }
            }
            foreach ($r in @($output)) { if ($r) { $results.Add($r) } }
            Write-EhcLog -Message ('{0}: done' -f $key)
        }
        catch {
            Write-EhcLog -Level 'ERROR' -Message ('{0}: {1}' -f $key, $_.Exception.Message)
            $results.Add((ConvertTo-EhcResult -Category $categoryName[$key] -Check 'Check execution' -Status 'Fail' -Detail ('Check threw an error: {0}' -f $_.Exception.Message)))
        }
    }

    if (-not $NoReport) {
        $reportFile = Export-EhcHtmlReport -Result $results.ToArray() -Path (Join-Path -Path $OutputPath -ChildPath 'index.html')
        $results | Select-Object -Property Category, Check, Target, Status, Detail, Timestamp |
            Export-Csv -Path (Join-Path -Path $OutputPath -ChildPath 'results.csv') -NoTypeInformation -Encoding UTF8 -WhatIf:$false -Confirm:$false
        $results | Select-Object -Property Category, Check, Target, Status, Detail, @{ Name = 'Timestamp'; Expression = { $_.Timestamp.ToString('o') } } |
            ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path -Path $OutputPath -ChildPath 'results.json') -Encoding UTF8 -WhatIf:$false -Confirm:$false
        Write-EhcLog -Message ('Report written: {0}' -f $reportFile.FullName)
        Write-Information -MessageData ('Report: {0}' -f $reportFile.FullName)
    }

    $summary = ($results | Group-Object -Property Status | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ' '
    Write-EhcLog -Message ('Health check complete. {0}' -f $summary)
    $results.ToArray()
}
