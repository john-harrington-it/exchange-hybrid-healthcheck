function Export-EhcHtmlReport {
    <#
    .SYNOPSIS
        Writes health check results to an HTML dashboard file.

    .DESCRIPTION
        Collects Ehc.Result objects from the pipeline and writes a self-contained HTML dashboard
        (overall status, counts by status, worst status per category, and a sortable findings
        table). Returns the report file.

    .PARAMETER Result
        Results from any Test-Ehc* command or Invoke-EhcHealthCheck.

    .PARAMETER Path
        Output HTML file path.

    .PARAMETER Title
        Report title.

    .EXAMPLE
        Test-EhcCertificate | Export-EhcHtmlReport -Path .\certs.html

    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [psobject[]]$Result,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [string]$Title = 'Exchange Hybrid Health Check'
    )

    begin {
        $all = New-Object -TypeName System.Collections.Generic.List[object]
    }
    process {
        foreach ($r in $Result) { $all.Add($r) }
    }
    end {
        $parent = Split-Path -Path $Path -Parent
        if ($parent -and -not (Test-Path -Path $parent)) {
            $null = New-Item -Path $parent -ItemType Directory -Force -WhatIf:$false -Confirm:$false
        }
        $html = ConvertTo-EhcHtmlDashboard -Result $all.ToArray() -Title $Title
        Set-Content -Path $Path -Value $html -Encoding UTF8 -WhatIf:$false -Confirm:$false
        Get-Item -Path $Path
    }
}
