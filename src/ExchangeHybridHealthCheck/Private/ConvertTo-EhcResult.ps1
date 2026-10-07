function ConvertTo-EhcResult {
    <#
    .SYNOPSIS
        Creates a standard health check result object.
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Check,

        [AllowEmptyString()]
        [string]$Target = '',

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warning', 'Fail', 'Info', 'Skipped')]
        [string]$Status,

        [AllowEmptyString()]
        [string]$Detail = ''
    )

    [pscustomobject]@{
        PSTypeName = 'Ehc.Result'
        Category   = $Category
        Check      = $Check
        Target     = $Target
        Status     = $Status
        Detail     = $Detail
        Timestamp  = Get-Date
    }
}
