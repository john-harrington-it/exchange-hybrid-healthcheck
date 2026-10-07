<#
.SYNOPSIS
    Example: daily Exchange hybrid health check from a management server.

.DESCRIPTION
    Loads the Exchange Management Shell remotely, connects to Exchange Online with the 'Cloud'
    prefix using certificate-based app-only auth (no stored password), runs every check, and
    writes the dashboard to a dated folder. Read-only.

.PARAMETER ExchangeServer
    On-premises Exchange server FQDN used for the remote PowerShell session.

.PARAMETER AppId
    Entra ID application (client) ID used for Exchange Online app-only authentication.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate registered on the app, in the local certificate store.

.PARAMETER Organization
    Tenant's initial domain, for example contoso.onmicrosoft.com.

.PARAMETER ReportRoot
    Folder that receives one dated sub-folder per run.

.EXAMPLE
    ./scheduled-healthcheck.ps1 -ExchangeServer ex01.contoso.local -AppId 00000000-0000-0000-0000-000000000000 -CertificateThumbprint ABCDEF -Organization contoso.onmicrosoft.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExchangeServer,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$AppId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]+$')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory)]
    [ValidatePattern('\.onmicrosoft\.com$')]
    [string]$Organization,

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = (Join-Path -Path (Get-Location).Path -ChildPath 'Exchange-Health')
)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/ExchangeHybridHealthCheck/ExchangeHybridHealthCheck.psd1') -Force

$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri ('http://{0}/PowerShell/' -f $ExchangeServer) -Authentication Kerberos
try {
    $null = Import-PSSession -Session $session -DisableNameChecking -AllowClobber
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $CertificateThumbprint -Organization $Organization -Prefix Cloud -ShowBanner:$false

    $results = Invoke-EhcHealthCheck -OutputPath (Join-Path -Path $ReportRoot -ChildPath (Get-Date -Format 'yyyy-MM-dd'))
    $results | Group-Object -Property Status | Select-Object -Property Name, Count | Format-Table -AutoSize
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Remove-PSSession -Session $session
}
