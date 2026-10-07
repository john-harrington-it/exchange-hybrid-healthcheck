function Test-EhcDatabaseHealth {
    <#
    .SYNOPSIS
        Checks mailbox database mount state, backup recency, and DAG copy health.

    .DESCRIPTION
        For every mailbox database (Get-MailboxDatabase -Status):
          * Fail when the database is not mounted.
          * Warning when no full or incremental backup is recorded within -BackupWarningHours
            (also a sign that transaction logs are not being truncated).
        When a database availability group exists, every copy on every DAG member is checked
        with Get-MailboxDatabaseCopyStatus:
          * Fail for Failed, FailedAndSuspended, Dismounted, or ServiceDown copies.
          * Warning for Suspended copies, copy or replay queues above threshold, or an
            unhealthy content index.
        Read-only.

    .PARAMETER Server
        Limit checks to these servers. Defaults to all DAG members / all databases.

    .PARAMETER CopyQueueThreshold
        Copy queue length that produces a Warning. Default 10.

    .PARAMETER ReplayQueueThreshold
        Replay queue length that produces a Warning. Default 50. Lagged copies are expected to
        exceed this; exclude them with -Server or review the result.

    .PARAMETER BackupWarningHours
        Hours since the last full or incremental backup that produce a Warning. Default 36.

    .EXAMPLE
        Test-EhcDatabaseHealth -BackupWarningHours 26

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Server,

        [ValidateRange(1, 100000)]
        [int]$CopyQueueThreshold = 10,

        [ValidateRange(1, 100000)]
        [int]$ReplayQueueThreshold = 50,

        [ValidateRange(1, 8760)]
        [int]$BackupWarningHours = 36
    )

    $category = 'Databases and DAG'
    if (-not (Test-EhcCommand -Name 'Get-MailboxDatabase')) {
        ConvertTo-EhcResult -Category $category -Check 'Database health' -Status 'Skipped' -Detail 'Exchange Management Shell cmdlets not loaded.'
        return
    }

    $now = Get-Date
    $databases = @(Get-MailboxDatabase -Status)
    if ($Server) { $databases = @($databases | Where-Object { [string]$_.Server -in $Server }) }

    foreach ($db in $databases) {
        $mountStatus = 'Pass'
        $mountDetail = 'Mounted on {0}' -f $db.Server
        if (-not $db.Mounted) { $mountStatus = 'Fail'; $mountDetail = 'NOT mounted (active server {0})' -f $db.Server }
        ConvertTo-EhcResult -Category $category -Check 'Database mounted' -Target ([string]$db.Name) -Status $mountStatus -Detail ('{0} | Size: {1}' -f $mountDetail, $db.DatabaseSize)

        $last = @($db.LastFullBackup, $db.LastIncrementalBackup) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        if (-not $last) {
            ConvertTo-EhcResult -Category $category -Check 'Backup recency' -Target ([string]$db.Name) -Status 'Warning' -Detail 'No backup recorded. Logs will not truncate without a backup or circular logging.'
        }
        else {
            $hours = [int][math]::Floor(($now - [datetime]$last).TotalHours)
            $status = 'Pass'
            if ($hours -gt $BackupWarningHours) { $status = 'Warning' }
            ConvertTo-EhcResult -Category $category -Check 'Backup recency' -Target ([string]$db.Name) -Status $status -Detail ('Last backup {0:yyyy-MM-dd HH:mm} ({1} hours ago)' -f ([datetime]$last), $hours)
        }
    }

    if (-not (Test-EhcCommand -Name 'Get-DatabaseAvailabilityGroup', 'Get-MailboxDatabaseCopyStatus')) { return }
    $dags = @(Get-DatabaseAvailabilityGroup)
    if ($dags.Count -eq 0) {
        ConvertTo-EhcResult -Category $category -Check 'DAG copy status' -Status 'Info' -Detail 'No database availability group; standalone databases only.'
        return
    }

    foreach ($dag in $dags) {
        $members = @($dag.Servers | ForEach-Object { [string]$_ })
        if ($Server) { $members = @($members | Where-Object { $_ -in $Server }) }
        foreach ($member in $members) {
            try {
                $copies = @(Get-MailboxDatabaseCopyStatus -Server $member -ErrorAction Stop)
            }
            catch {
                ConvertTo-EhcResult -Category $category -Check 'DAG copy status' -Target ('{0}\{1}' -f $dag.Name, $member) -Status 'Fail' -Detail ('Could not read copy status: {0}' -f $_.Exception.Message)
                continue
            }
            foreach ($copy in $copies) {
                $state = [string]$copy.Status
                $notes = New-Object -TypeName System.Collections.Generic.List[string]
                $status = 'Pass'
                if ($state -in @('Failed', 'FailedAndSuspended', 'Dismounted', 'ServiceDown', 'DisconnectedAndResynchronizing')) { $status = 'Fail' }
                elseif ($state -notin @('Mounted', 'Healthy')) { $status = 'Warning' }

                if ([int]$copy.CopyQueueLength -gt $CopyQueueThreshold) { $notes.Add(('Copy queue {0}' -f $copy.CopyQueueLength)); if ($status -eq 'Pass') { $status = 'Warning' } }
                if ([int]$copy.ReplayQueueLength -gt $ReplayQueueThreshold) { $notes.Add(('Replay queue {0}' -f $copy.ReplayQueueLength)); if ($status -eq 'Pass') { $status = 'Warning' } }
                $ci = [string]$copy.ContentIndexState
                if ($ci -and $ci -notin @('Healthy', 'NotApplicable', 'HealthyAndUpgrading')) { $notes.Add(('Content index {0}' -f $ci)); if ($status -eq 'Pass') { $status = 'Warning' } }

                $detail = 'Status: {0} | CopyQueue: {1} | ReplayQueue: {2} | ContentIndex: {3}' -f $state, $copy.CopyQueueLength, $copy.ReplayQueueLength, $ci
                if ($notes.Count -gt 0) { $detail = '{0} | {1}' -f ($notes -join '; '), $detail }
                ConvertTo-EhcResult -Category $category -Check 'DAG copy status' -Target ([string]$copy.Name) -Status $status -Detail $detail
            }
        }
    }
}
