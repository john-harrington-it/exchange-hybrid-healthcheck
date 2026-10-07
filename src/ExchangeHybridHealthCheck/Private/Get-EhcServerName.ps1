function Get-EhcServerName {
    <#
    .SYNOPSIS
        Resolves the list of Exchange 2016/2019 mailbox servers to check.
    #>
    [CmdletBinding()]
    [OutputType([string], [string[]])]
    param(
        [string[]]$Server
    )

    if ($Server) { return $Server }
    Get-ExchangeServer -ErrorAction Stop |
        Where-Object { [string]$_.ServerRole -match 'Mailbox' -and [string]$_.AdminDisplayVersion -match 'Version 15' } |
        ForEach-Object { [string]$_.Name }
}
