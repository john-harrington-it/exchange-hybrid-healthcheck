function Write-EhcLog {
    <#
    .SYNOPSIS
        Writes a timestamped line to the verbose stream and, when configured, to the run log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Verbose -Message $line
    if ($script:EhcLogPath) {
        try {
            Add-Content -Path $script:EhcLogPath -Value $line -Encoding UTF8 -WhatIf:$false -Confirm:$false -ErrorAction Stop
        }
        catch {
            Write-Verbose -Message ("Could not write to log file: {0}" -f $_.Exception.Message)
        }
    }
}
