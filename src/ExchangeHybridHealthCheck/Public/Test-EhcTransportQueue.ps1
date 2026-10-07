function Test-EhcTransportQueue {
    <#
    .SYNOPSIS
        Checks transport queues on each Exchange mailbox server.

    .DESCRIPTION
        Reads queues with Get-Queue on each server and flags:
          * Queues in Retry status (with the last error), Fail if also above the critical size.
          * Queues above -WarningThreshold or -CriticalThreshold messages.
          * Any messages in the poison message queue.
        A single Pass result per server summarizes healthy queues. Read-only.

    .PARAMETER Server
        Exchange servers to check. Defaults to all Exchange 2016/2019 mailbox servers.

    .PARAMETER WarningThreshold
        Message count that produces a Warning. Default 100.

    .PARAMETER CriticalThreshold
        Message count that produces a Fail. Default 1000.

    .EXAMPLE
        Test-EhcTransportQueue -Server EX01, EX02 -WarningThreshold 50

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Server,

        [ValidateRange(1, 1000000)]
        [int]$WarningThreshold = 100,

        [ValidateRange(1, 1000000)]
        [int]$CriticalThreshold = 1000
    )

    $category = 'Transport queues'
    if (-not (Test-EhcCommand -Name 'Get-Queue', 'Get-ExchangeServer')) {
        ConvertTo-EhcResult -Category $category -Check 'Queue health' -Status 'Skipped' -Detail 'Exchange Management Shell cmdlets not loaded.'
        return
    }

    foreach ($s in (Get-EhcServerName -Server $Server)) {
        try {
            $queues = @(Get-Queue -Server $s -ErrorAction Stop)
        }
        catch {
            ConvertTo-EhcResult -Category $category -Check 'Queue health' -Target $s -Status 'Fail' -Detail ('Could not read queues: {0}' -f $_.Exception.Message)
            continue
        }

        $issues = 0
        $total = 0
        foreach ($q in $queues) {
            $count = [int]$q.MessageCount
            $total += $count
            $isPoison = ([string]$q.Identity -like '*\Poison') -or ([string]$q.NextHopDomain -eq 'Poison Message')

            $status = $null
            if ($isPoison -and $count -gt 0) { $status = 'Warning' }
            if ([string]$q.Status -eq 'Retry') { $status = 'Warning' }
            if ($count -ge $WarningThreshold) { $status = 'Warning' }
            if ($count -ge $CriticalThreshold) { $status = 'Fail' }

            if ($status) {
                $issues++
                $detail = 'Messages: {0} | Status: {1} | Next hop: {2} | Delivery: {3}' -f $count, $q.Status, $q.NextHopDomain, $q.DeliveryType
                if ($q.LastError) { $detail = '{0} | Last error: {1}' -f $detail, $q.LastError }
                ConvertTo-EhcResult -Category $category -Check 'Queue health' -Target ([string]$q.Identity) -Status $status -Detail $detail
            }
        }
        if ($issues -eq 0) {
            ConvertTo-EhcResult -Category $category -Check 'Queue health' -Target $s -Status 'Pass' -Detail ('{0} queue(s), {1} message(s) queued, no issues.' -f $queues.Count, $total)
        }
    }
}
