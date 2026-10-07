function Test-EhcHybridConfiguration {
    <#
    .SYNOPSIS
        Validates the hybrid configuration on-premises and in Exchange Online.

    .DESCRIPTION
        On-premises (Exchange Management Shell):
          * Hybrid configuration object exists (created by the Hybrid Configuration Wizard).
          * The hybrid TLS certificate (TlsCertificateName) is present on each sending and
            receiving transport server, and is not close to expiry.
          * Organization relationships are enabled with free/busy sharing.
          * The OAuth intra-organization connector is enabled.
        Exchange Online (prefixed cmdlets, default prefix 'Cloud'):
          * On-premises organization object exists.
          * Organization relationship and intra-organization connector are enabled.
        Read-only.

    .PARAMETER CloudPrefix
        Prefix used with Connect-ExchangeOnline -Prefix. Default 'Cloud'.

    .PARAMETER WarningDays
        Days before hybrid certificate expiry that produce a Warning. Default 30.

    .EXAMPLE
        Connect-ExchangeOnline -Prefix Cloud
        Test-EhcHybridConfiguration

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidatePattern('^[A-Za-z]*$')]
        [string]$CloudPrefix = 'Cloud',

        [ValidateRange(1, 365)]
        [int]$WarningDays = 30
    )

    $category = 'Hybrid configuration'

    # ---------- On-premises ----------
    if (Test-EhcCommand -Name 'Get-HybridConfiguration') {
        $hc = Get-HybridConfiguration
        if (-not $hc) {
            ConvertTo-EhcResult -Category $category -Check 'Hybrid configuration object' -Target 'On-premises' -Status 'Fail' -Detail 'No hybrid configuration found. Run the Hybrid Configuration Wizard.'
        }
        else {
            ConvertTo-EhcResult -Category $category -Check 'Hybrid configuration object' -Target 'On-premises' -Status 'Pass' -Detail ('Features: {0} | Domains: {1}' -f (@($hc.Features) -join ', '), (@($hc.Domains) -join ', '))

            $tlsName = [string]$hc.TlsCertificateName
            if (-not $tlsName) {
                ConvertTo-EhcResult -Category $category -Check 'Hybrid TLS certificate' -Target 'On-premises' -Status 'Fail' -Detail 'TlsCertificateName is not set on the hybrid configuration.'
            }
            elseif (Test-EhcCommand -Name 'Get-ExchangeCertificate') {
                $servers = @(@($hc.SendingTransportServers) + @($hc.ReceivingTransportServers) | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
                foreach ($s in $servers) {
                    $match = @(Get-ExchangeCertificate -Server $s -ErrorAction SilentlyContinue | Where-Object { ('<I>{0}<S>{1}' -f $_.Issuer, $_.Subject) -eq $tlsName })
                    if ($match.Count -eq 0) {
                        ConvertTo-EhcResult -Category $category -Check 'Hybrid TLS certificate' -Target $s -Status 'Fail' -Detail ('Certificate {0} not found on this transport server.' -f $tlsName)
                        continue
                    }
                    $cert = $match | Sort-Object -Property NotAfter -Descending | Select-Object -First 1
                    $days = [int][math]::Floor(([datetime]$cert.NotAfter - (Get-Date)).TotalDays)
                    $status = Get-EhcExpiryStatus -DaysLeft $days -WarningDays $WarningDays -CriticalDays 14
                    ConvertTo-EhcResult -Category $category -Check 'Hybrid TLS certificate' -Target $s -Status $status -Detail ('Found ({0}); expires {1:yyyy-MM-dd} ({2} days)' -f $cert.Thumbprint, ([datetime]$cert.NotAfter), $days)
                }
            }
        }
    }
    else {
        ConvertTo-EhcResult -Category $category -Check 'Hybrid configuration object' -Target 'On-premises' -Status 'Skipped' -Detail 'Exchange Management Shell cmdlets not loaded.'
    }

    if (Test-EhcCommand -Name 'Get-OrganizationRelationship') {
        foreach ($rel in @(Get-OrganizationRelationship)) {
            $status = 'Pass'; $note = 'Enabled'
            if (-not $rel.Enabled) { $status = 'Fail'; $note = 'Disabled' }
            elseif (-not $rel.FreeBusyAccessEnabled) { $status = 'Warning'; $note = 'Enabled, but free/busy sharing is off' }
            ConvertTo-EhcResult -Category $category -Check 'Organization relationship' -Target ('On-premises: {0}' -f $rel.Name) -Status $status -Detail ('{0} | Domains: {1}' -f $note, (@($rel.DomainNames) -join ', '))
        }
    }
    if (Test-EhcCommand -Name 'Get-IntraOrganizationConnector') {
        $ioc = @(Get-IntraOrganizationConnector)
        if ($ioc.Count -eq 0) {
            ConvertTo-EhcResult -Category $category -Check 'OAuth (intra-organization connector)' -Target 'On-premises' -Status 'Warning' -Detail 'No intra-organization connector; hybrid relies on DAuth (classic) for free/busy.'
        }
        foreach ($c in $ioc) {
            $status = 'Pass'
            if (-not $c.Enabled) { $status = 'Fail' }
            ConvertTo-EhcResult -Category $category -Check 'OAuth (intra-organization connector)' -Target ('On-premises: {0}' -f $c.Name) -Status $status -Detail ('Enabled: {0} | Discovery endpoint: {1}' -f $c.Enabled, $c.DiscoveryEndpoint)
        }
    }

    # ---------- Exchange Online ----------
    $onPremOrgCmd = Get-EhcCloudCommandName -Noun 'OnPremisesOrganization' -Prefix $CloudPrefix
    if (-not (Test-EhcCommand -Name $onPremOrgCmd)) {
        ConvertTo-EhcResult -Category $category -Check 'On-premises organization object' -Target 'Exchange Online' -Status 'Skipped' -Detail ('{0} not available. Connect with Connect-ExchangeOnline -Prefix {1}.' -f $onPremOrgCmd, $CloudPrefix)
        return
    }

    $org = @(& $onPremOrgCmd)
    if ($org.Count -eq 0) {
        ConvertTo-EhcResult -Category $category -Check 'On-premises organization object' -Target 'Exchange Online' -Status 'Fail' -Detail 'No OnPremisesOrganization object in Exchange Online. Re-run the Hybrid Configuration Wizard.'
    }
    foreach ($o in $org) {
        ConvertTo-EhcResult -Category $category -Check 'On-premises organization object' -Target 'Exchange Online' -Status 'Pass' -Detail ('{0} | Hybrid domains: {1} | Inbound connector: {2} | Outbound connector: {3}' -f $o.Name, (@($o.HybridDomains) -join ', '), $o.InboundConnector, $o.OutboundConnector)
    }

    $relCmd = Get-EhcCloudCommandName -Noun 'OrganizationRelationship' -Prefix $CloudPrefix
    if (Test-EhcCommand -Name $relCmd) {
        foreach ($rel in @(& $relCmd)) {
            $status = 'Pass'
            if (-not $rel.Enabled) { $status = 'Fail' }
            ConvertTo-EhcResult -Category $category -Check 'Organization relationship' -Target ('Exchange Online: {0}' -f $rel.Name) -Status $status -Detail ('Enabled: {0} | Free/busy: {1}' -f $rel.Enabled, $rel.FreeBusyAccessEnabled)
        }
    }
    $iocCmd = Get-EhcCloudCommandName -Noun 'IntraOrganizationConnector' -Prefix $CloudPrefix
    if (Test-EhcCommand -Name $iocCmd) {
        foreach ($c in @(& $iocCmd)) {
            $status = 'Pass'
            if (-not $c.Enabled) { $status = 'Fail' }
            ConvertTo-EhcResult -Category $category -Check 'OAuth (intra-organization connector)' -Target ('Exchange Online: {0}' -f $c.Name) -Status $status -Detail ('Enabled: {0} | Discovery endpoint: {1}' -f $c.Enabled, $c.DiscoveryEndpoint)
        }
    }
}
