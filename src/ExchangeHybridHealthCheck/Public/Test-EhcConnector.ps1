function Test-EhcConnector {
    <#
    .SYNOPSIS
        Checks the hybrid mail flow connectors on both sides.

    .DESCRIPTION
        On-premises:
          * A send connector routes to the tenant's *.mail.onmicrosoft.com address space, is
            enabled, requires TLS with DomainValidation, and has a TLS certificate configured.
          * Default Frontend receive connectors have TlsCertificateName set (the Hybrid
            Configuration Wizard sets this so Exchange Online can authenticate on-premises).
        Exchange Online (prefixed cmdlets):
          * An enabled OnPremises inbound connector with TLS sender certificate name.
          * An enabled OnPremises outbound connector with smart hosts and TLS settings.
        Read-only.

    .PARAMETER CloudPrefix
        Prefix used with Connect-ExchangeOnline -Prefix. Default 'Cloud'.

    .EXAMPLE
        Test-EhcConnector | Format-Table Status, Check, Target, Detail -Wrap

    .OUTPUTS
        Ehc.Result
    #>
    [CmdletBinding()]
    [OutputType('Ehc.Result')]
    param(
        [ValidatePattern('^[A-Za-z]*$')]
        [string]$CloudPrefix = 'Cloud'
    )

    $category = 'Mail flow connectors'

    if (Test-EhcCommand -Name 'Get-SendConnector', 'Get-ReceiveConnector') {
        $toCloud = @(Get-SendConnector | Where-Object { (@($_.AddressSpaces) -join ';') -match 'mail\.onmicrosoft\.com' })
        if ($toCloud.Count -eq 0) {
            ConvertTo-EhcResult -Category $category -Check 'Send connector to Exchange Online' -Target 'On-premises' -Status 'Fail' -Detail 'No send connector for *.mail.onmicrosoft.com. Hybrid mail flow to the cloud will not route.'
        }
        foreach ($c in $toCloud) {
            $issues = New-Object -TypeName System.Collections.Generic.List[string]
            if (-not $c.RequireTLS) { $issues.Add('RequireTLS is off') }
            if ([string]$c.TlsAuthLevel -ne 'DomainValidation') { $issues.Add(('TlsAuthLevel is {0}, expected DomainValidation' -f $c.TlsAuthLevel)) }
            if (-not $c.TlsCertificateName) { $issues.Add('TlsCertificateName not set') }
            $status = 'Pass'
            if (-not $c.Enabled) { $status = 'Fail'; $issues.Insert(0, 'Connector is disabled') }
            elseif ($issues.Count -gt 0) { $status = 'Warning' }
            $detail = 'Address space: {0} | TLS domain: {1}' -f (@($c.AddressSpaces) -join ', '), $c.TlsDomain
            if ($issues.Count -gt 0) { $detail = '{0} | {1}' -f ($issues -join '; '), $detail }
            ConvertTo-EhcResult -Category $category -Check 'Send connector to Exchange Online' -Target ('On-premises: {0}' -f $c.Name) -Status $status -Detail $detail
        }

        foreach ($rc in @(Get-ReceiveConnector | Where-Object { $_.Name -like 'Default Frontend*' })) {
            $status = 'Pass'
            $detail = 'TlsCertificateName: {0}' -f $rc.TlsCertificateName
            if (-not $rc.TlsCertificateName) { $status = 'Warning'; $detail = 'TlsCertificateName not set; Exchange Online cannot match the hybrid certificate on inbound TLS.' }
            ConvertTo-EhcResult -Category $category -Check 'Receive connector TLS' -Target ('On-premises: {0}' -f $rc.Identity) -Status $status -Detail $detail
        }
    }
    else {
        ConvertTo-EhcResult -Category $category -Check 'On-premises connectors' -Target 'On-premises' -Status 'Skipped' -Detail 'Exchange Management Shell cmdlets not loaded.'
    }

    $inCmd = Get-EhcCloudCommandName -Noun 'InboundConnector' -Prefix $CloudPrefix
    $outCmd = Get-EhcCloudCommandName -Noun 'OutboundConnector' -Prefix $CloudPrefix
    if (-not (Test-EhcCommand -Name $inCmd, $outCmd)) {
        ConvertTo-EhcResult -Category $category -Check 'Exchange Online connectors' -Target 'Exchange Online' -Status 'Skipped' -Detail ('{0}/{1} not available. Connect with Connect-ExchangeOnline -Prefix {2}.' -f $inCmd, $outCmd, $CloudPrefix)
        return
    }

    $inbound = @(& $inCmd | Where-Object { [string]$_.ConnectorType -eq 'OnPremises' })
    if ($inbound.Count -eq 0) {
        ConvertTo-EhcResult -Category $category -Check 'Inbound connector from on-premises' -Target 'Exchange Online' -Status 'Fail' -Detail 'No OnPremises inbound connector found.'
    }
    foreach ($c in $inbound) {
        $status = 'Pass'; $notes = @()
        if (-not $c.Enabled) { $status = 'Fail'; $notes += 'Connector is disabled' }
        if (-not $c.TlsSenderCertificateName) { if ($status -eq 'Pass') { $status = 'Warning' }; $notes += 'TlsSenderCertificateName not set' }
        if (-not $c.RequireTls) { if ($status -eq 'Pass') { $status = 'Warning' }; $notes += 'RequireTls is off' }
        $notes += ('TLS sender certificate: {0}' -f $c.TlsSenderCertificateName)
        ConvertTo-EhcResult -Category $category -Check 'Inbound connector from on-premises' -Target ('Exchange Online: {0}' -f $c.Name) -Status $status -Detail ($notes -join ' | ')
    }

    $outbound = @(& $outCmd | Where-Object { [string]$_.ConnectorType -eq 'OnPremises' })
    if ($outbound.Count -eq 0) {
        ConvertTo-EhcResult -Category $category -Check 'Outbound connector to on-premises' -Target 'Exchange Online' -Status 'Fail' -Detail 'No OnPremises outbound connector found.'
    }
    foreach ($c in $outbound) {
        $status = 'Pass'; $notes = @()
        if (-not $c.Enabled) { $status = 'Fail'; $notes += 'Connector is disabled' }
        if (@($c.SmartHosts).Count -eq 0) { $status = 'Fail'; $notes += 'No smart hosts configured' }
        if ([string]$c.TlsSettings -notin @('DomainValidation', 'CertificateValidation')) { if ($status -eq 'Pass') { $status = 'Warning' }; $notes += ('TlsSettings is {0}' -f $c.TlsSettings) }
        $notes += ('Smart hosts: {0}' -f (@($c.SmartHosts) -join ', '))
        ConvertTo-EhcResult -Category $category -Check 'Outbound connector to on-premises' -Target ('Exchange Online: {0}' -f $c.Name) -Status $status -Detail ($notes -join ' | ')
    }
}
