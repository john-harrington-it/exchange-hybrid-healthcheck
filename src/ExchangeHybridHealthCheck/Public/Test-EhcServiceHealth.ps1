function Test-EhcServiceHealth {
    <#
    .SYNOPSIS
        Verifies that required Exchange services are running on each server.

    .DESCRIPTION
        Runs Test-ServiceHealth (itself read-only) against each server and returns one result per
        server: Pass when every role reports RequiredServicesRunning, otherwise Fail with the list
        of stopped services. Read-only.

    .PARAMETER Server
        Exchange servers to check. Defaults to all Exchange 2016/2019 mailbox servers.

    .EXAMPLE
        Test-EhcServiceHealth -Server EX01

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Server
    )

    $category = 'Services'
    if (-not (Test-EhcCommand -Name 'Test-ServiceHealth', 'Get-ExchangeServer')) {
        ConvertTo-EhcResult -Category $category -Check 'Required services' -Status 'Skipped' -Detail 'Exchange Management Shell cmdlets not loaded.'
        return
    }

    foreach ($s in (Get-EhcServerName -Server $Server)) {
        try {
            $roles = @(Test-ServiceHealth -Server $s -ErrorAction Stop)
        }
        catch {
            ConvertTo-EhcResult -Category $category -Check 'Required services' -Target $s -Status 'Fail' -Detail ('Could not query services: {0}' -f $_.Exception.Message)
            continue
        }
        $stopped = @($roles | Where-Object { -not $_.RequiredServicesRunning } | ForEach-Object { @($_.ServicesNotRunning) } | Where-Object { $_ } | Sort-Object -Unique)
        if ($stopped.Count -gt 0) {
            ConvertTo-EhcResult -Category $category -Check 'Required services' -Target $s -Status 'Fail' -Detail ('Not running: {0}' -f ($stopped -join ', '))
        }
        else {
            ConvertTo-EhcResult -Category $category -Check 'Required services' -Target $s -Status 'Pass' -Detail ('All required services running ({0} role check(s)).' -f $roles.Count)
        }
    }
}
