function Get-EhcCloudCommandName {
    <#
    .SYNOPSIS
        Returns the prefixed Exchange Online cmdlet name (for example Get-CloudMigrationBatch).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Noun,

        [AllowEmptyString()]
        [string]$Prefix = 'Cloud'
    )

    return ('Get-{0}{1}' -f $Prefix, $Noun)
}
