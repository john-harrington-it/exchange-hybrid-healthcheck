function Test-EhcMigrationBatch {
    <#
    .SYNOPSIS
        Reports the status of Exchange Online mailbox migration batches.

    .DESCRIPTION
        Reads migration batches with the prefixed Get-MigrationBatch cmdlet and rates each one:
        Fail for Failed batches, Warning for batches that completed or synced with errors, are
        stopped, or have failed users, Pass otherwise. With -IncludeFailedUser, each failed
        migration user is listed with its error summary. Read-only.

    .PARAMETER CloudPrefix
        Prefix used with Connect-ExchangeOnline -Prefix. Default 'Cloud'.

    .PARAMETER IncludeFailedUser
        Add one result per failed migration user.

    .EXAMPLE
        Test-EhcMigrationBatch -IncludeFailedUser | Where-Object Status -in 'Fail','Warning'

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidatePattern('^[A-Za-z]*$')]
        [string]$CloudPrefix = 'Cloud',

        [switch]$IncludeFailedUser
    )

    $category = 'Migration batches'
    $batchCmd = Get-EhcCloudCommandName -Noun 'MigrationBatch' -Prefix $CloudPrefix
    if (-not (Test-EhcCommand -Name $batchCmd)) {
        ConvertTo-EhcResult -Category $category -Check 'Migration batch status' -Target 'Exchange Online' -Status 'Skipped' -Detail ('{0} not available. Connect with Connect-ExchangeOnline -Prefix {1}.' -f $batchCmd, $CloudPrefix)
        return
    }

    $batches = @(& $batchCmd)
    if ($batches.Count -eq 0) {
        ConvertTo-EhcResult -Category $category -Check 'Migration batch status' -Target 'Exchange Online' -Status 'Info' -Detail 'No migration batches found.'
        return
    }

    $userCmd = Get-EhcCloudCommandName -Noun 'MigrationUser' -Prefix $CloudPrefix
    foreach ($b in $batches) {
        $state = [string]$b.Status
        $failed = 0
        if ($b.FailedCount) { $failed = [int]$b.FailedCount }

        $status = 'Pass'
        if ($state -in @('Failed', 'Corrupted')) { $status = 'Fail' }
        elseif ($state -in @('CompletedWithErrors', 'SyncedWithErrors', 'Stopped', 'IncrementalSyncInterrupted') -or $failed -gt 0) { $status = 'Warning' }

        $detail = 'Status: {0} | Total: {1} | Synced: {2} | Finalized: {3} | Failed: {4} | Last synced: {5}' -f $state, $b.TotalCount, $b.SyncedCount, $b.FinalizedCount, $failed, $b.LastSyncedDateTime
        ConvertTo-EhcResult -Category $category -Check 'Migration batch status' -Target ([string]$b.Identity) -Status $status -Detail $detail

        if ($IncludeFailedUser -and $failed -gt 0 -and (Test-EhcCommand -Name $userCmd)) {
            foreach ($u in @(& $userCmd -BatchId ([string]$b.Identity) -Status 'Failed')) {
                ConvertTo-EhcResult -Category $category -Check 'Failed migration user' -Target ([string]$u.Identity) -Status 'Fail' -Detail ('Batch {0}: {1}' -f $b.Identity, $u.ErrorSummary)
            }
        }
    }
}
