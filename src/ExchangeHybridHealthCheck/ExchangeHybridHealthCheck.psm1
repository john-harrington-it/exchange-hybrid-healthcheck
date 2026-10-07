# ExchangeHybridHealthCheck module loader.
# Every check is read-only. Exchange cmdlets come from the Exchange Management Shell (on-premises)
# and from ExchangeOnlineManagement connected with a prefix (default 'Cloud'), for example:
#   Connect-ExchangeOnline -Prefix Cloud
# Checks whose cmdlets are not loaded return a 'Skipped' result instead of failing.

$script:EhcLogPath = $null

$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
