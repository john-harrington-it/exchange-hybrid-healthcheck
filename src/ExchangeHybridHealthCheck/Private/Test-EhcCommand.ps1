function Test-EhcCommand {
    <#
    .SYNOPSIS
        Returns $true when every named command is available in the session.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name
    )

    foreach ($n in $Name) {
        if (-not (Get-Command -Name $n -ErrorAction SilentlyContinue)) { return $false }
    }
    return $true
}
