function Get-EhcExpiryStatus {
    <#
    .SYNOPSIS
        Maps days-until-expiry to Pass, Warning, or Fail.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int]$DaysLeft,

        [int]$WarningDays = 30,

        [int]$CriticalDays = 14
    )

    if ($DaysLeft -le $CriticalDays) { return 'Fail' }
    if ($DaysLeft -le $WarningDays) { return 'Warning' }
    return 'Pass'
}
