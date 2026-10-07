function Test-EhcCertificate {
    <#
    .SYNOPSIS
        Checks Exchange certificate expiry on each mailbox server.

    .DESCRIPTION
        Reads certificates with Get-ExchangeCertificate on every Exchange 2016/2019 mailbox server
        (or the servers given in -Server) and rates each certificate that is bound to a service:
        Fail when expired or within -CriticalDays, Warning within -WarningDays, otherwise Pass.
        Unassigned certificates are skipped unless -IncludeUnassigned is set. Read-only.

    .PARAMETER Server
        Exchange servers to check. Defaults to all Exchange 2016/2019 mailbox servers.

    .PARAMETER WarningDays
        Days before expiry that produce a Warning. Default 30.

    .PARAMETER CriticalDays
        Days before expiry that produce a Fail. Default 14.

    .PARAMETER IncludeUnassigned
        Also report certificates that are not bound to any Exchange service.

    .EXAMPLE
        Test-EhcCertificate -WarningDays 45 | Where-Object Status -ne 'Pass'

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Server,

        [ValidateRange(1, 365)]
        [int]$WarningDays = 30,

        [ValidateRange(0, 365)]
        [int]$CriticalDays = 14,

        [switch]$IncludeUnassigned
    )

    $category = 'Certificates'
    if (-not (Test-EhcCommand -Name 'Get-ExchangeCertificate', 'Get-ExchangeServer')) {
        ConvertTo-EhcResult -Category $category -Check 'Certificate expiry' -Status 'Skipped' -Detail 'Exchange Management Shell cmdlets not loaded.'
        return
    }

    $now = Get-Date
    foreach ($s in (Get-EhcServerName -Server $Server)) {
        try {
            $certs = @(Get-ExchangeCertificate -Server $s -ErrorAction Stop)
        }
        catch {
            ConvertTo-EhcResult -Category $category -Check 'Certificate expiry' -Target $s -Status 'Fail' -Detail ('Could not read certificates: {0}' -f $_.Exception.Message)
            continue
        }

        foreach ($cert in $certs) {
            $services = [string]$cert.Services
            if (-not $IncludeUnassigned -and ([string]::IsNullOrWhiteSpace($services) -or $services -eq 'None')) { continue }

            $daysLeft = [int][math]::Floor(([datetime]$cert.NotAfter - $now).TotalDays)
            $status = Get-EhcExpiryStatus -DaysLeft $daysLeft -WarningDays $WarningDays -CriticalDays $CriticalDays
            $state = 'expires'
            if ($daysLeft -lt 0) { $state = 'EXPIRED' }
            $detail = '{0} | Services: {1} | {2} {3:yyyy-MM-dd} ({4} days) | Thumbprint {5}' -f $cert.Subject, $services, $state, ([datetime]$cert.NotAfter), $daysLeft, $cert.Thumbprint
            ConvertTo-EhcResult -Category $category -Check 'Certificate expiry' -Target $s -Status $status -Detail $detail
        }
    }
}
