# Unit tests for ExchangeHybridHealthCheck. No Exchange server or tenant is needed: Exchange
# cmdlets are stubbed and mocked, so the suite runs anywhere PowerShell runs.

BeforeAll {
    $stubs = @(
        'Get-ExchangeServer', 'Get-ExchangeCertificate', 'Get-HybridConfiguration', 'Get-OrganizationRelationship',
        'Get-IntraOrganizationConnector', 'Get-SendConnector', 'Get-ReceiveConnector', 'Get-Queue',
        'Get-MailboxDatabase', 'Get-DatabaseAvailabilityGroup', 'Get-MailboxDatabaseCopyStatus', 'Test-ServiceHealth',
        'Get-CloudOnPremisesOrganization', 'Get-CloudOrganizationRelationship', 'Get-CloudIntraOrganizationConnector',
        'Get-CloudInboundConnector', 'Get-CloudOutboundConnector', 'Get-CloudMigrationBatch'
    )
    foreach ($name in $stubs) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
            $null = New-Item -Path "function:global:$name" -Force -Value {
                [CmdletBinding()]
                param($Server, $Identity, [switch]$Status, $BatchId)
            }
        }
    }

    if (-not (Get-Command -Name 'Get-CloudMigrationUser' -ErrorAction SilentlyContinue)) {
        # Get-MigrationUser takes -Status as a value (not a switch), so it gets its own stub.
        $null = New-Item -Path 'function:global:Get-CloudMigrationUser' -Force -Value {
            [CmdletBinding()]
            param($Identity, $BatchId, $Status)
        }
    }

    $manifest = [System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'ExchangeHybridHealthCheck', 'ExchangeHybridHealthCheck.psd1')
    Import-Module -Name $manifest -Force
    $script:Now = Get-Date
}

AfterAll {
    Remove-Module -Name ExchangeHybridHealthCheck -Force -ErrorAction SilentlyContinue
}

Describe 'Read-only guarantee' {
    It 'never calls a state-changing Exchange or system cmdlet' {
        $src = [System.IO.Path]::Combine($PSScriptRoot, '..', 'src')
        $allowed = @('New-Object', 'New-Item', 'Set-Content', 'Add-Content', 'Export-Csv', 'Write-EhcLog', 'Write-Verbose', 'Write-Information', 'Write-Warning')
        $mutatingVerbs = '^(Set|New|Remove|Enable|Disable|Add|Update|Start|Stop|Restart|Move|Mount|Dismount|Resume|Suspend|Clear|Retry|Import|Install|Uninstall|Register|Unregister|Invoke)-'
        $offenders = foreach ($file in Get-ChildItem -Path $src -Recurse -Filter '*.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } |
                Where-Object { $_ -and $_ -match $mutatingVerbs -and $_ -notin $allowed } |
                ForEach-Object { '{0}: {1}' -f $file.Name, $_ }
        }
        $offenders | Should -BeNullOrEmpty
    }
}

Describe 'Test-EhcCertificate' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Get-ExchangeServer {
            [pscustomobject]@{ Name = 'EX01'; ServerRole = 'Mailbox'; AdminDisplayVersion = 'Version 15.2 (Build 1544.4)' }
            [pscustomobject]@{ Name = 'EX2010'; ServerRole = 'Mailbox, ClientAccess'; AdminDisplayVersion = 'Version 14.3 (Build 123.4)' }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-ExchangeCertificate {
            [pscustomobject]@{ Subject = 'CN=mail.contoso.com'; Services = 'IMAP, POP, IIS, SMTP'; NotAfter = $script:Now.AddDays(200); Thumbprint = 'AAA111' }
            [pscustomobject]@{ Subject = 'CN=legacy.contoso.com'; Services = 'IIS'; NotAfter = $script:Now.AddDays(20); Thumbprint = 'BBB222' }
            [pscustomobject]@{ Subject = 'CN=old.contoso.com'; Services = 'SMTP'; NotAfter = $script:Now.AddDays(-3); Thumbprint = 'CCC333' }
            [pscustomobject]@{ Subject = 'CN=unused'; Services = 'None'; NotAfter = $script:Now.AddDays(-100); Thumbprint = 'DDD444' }
        }
    }

    It 'rates certificates by days to expiry' {
        $r = Test-EhcCertificate
        ($r | Where-Object Detail -Match 'AAA111').Status | Should -Be 'Pass'
        ($r | Where-Object Detail -Match 'BBB222').Status | Should -Be 'Warning'
        ($r | Where-Object Detail -Match 'CCC333').Status | Should -Be 'Fail'
        ($r | Where-Object Detail -Match 'CCC333').Detail | Should -Match 'EXPIRED'
    }

    It 'skips unassigned certificates by default' {
        (Test-EhcCertificate).Detail -join ' ' | Should -Not -Match 'DDD444'
        (Test-EhcCertificate -IncludeUnassigned).Detail -join ' ' | Should -Match 'DDD444'
    }

    It 'only checks Exchange 2016/2019 (version 15) servers by default' {
        $null = Test-EhcCertificate
        Should -Invoke -ModuleName ExchangeHybridHealthCheck Get-ExchangeCertificate -ParameterFilter { $Server -eq 'EX2010' } -Times 0 -Exactly
    }

    It 'returns Fail when a server cannot be queried' {
        Mock -ModuleName ExchangeHybridHealthCheck Get-ExchangeCertificate { throw 'RPC server unavailable' }
        $r = @(Test-EhcCertificate -Server 'EX09')
        $r[0].Status | Should -Be 'Fail'
        $r[0].Detail | Should -Match 'RPC server unavailable'
    }

    It 'returns Skipped when the Exchange cmdlets are not loaded' {
        Mock -ModuleName ExchangeHybridHealthCheck Test-EhcCommand { $false }
        (Test-EhcCertificate).Status | Should -Be 'Skipped'
    }
}

Describe 'Test-EhcHybridConfiguration' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Get-HybridConfiguration {
            [pscustomobject]@{ Features = @('FreeBusy', 'MoveMailbox', 'Mailtips'); Domains = @('contoso.com'); TlsCertificateName = '<I>CN=R3, O=Example CA<S>CN=mail.contoso.com'; SendingTransportServers = @('EX01'); ReceivingTransportServers = @('EX01', 'EX02') }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-ExchangeCertificate -ParameterFilter { $Server -eq 'EX01' } {
            [pscustomobject]@{ Issuer = 'CN=R3, O=Example CA'; Subject = 'CN=mail.contoso.com'; NotAfter = $script:Now.AddDays(90); Thumbprint = 'AAA111' }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-ExchangeCertificate -ParameterFilter { $Server -eq 'EX02' } { }
        Mock -ModuleName ExchangeHybridHealthCheck Get-OrganizationRelationship {
            [pscustomobject]@{ Name = 'On-premises to O365'; Enabled = $true; FreeBusyAccessEnabled = $false; DomainNames = @('contoso.mail.onmicrosoft.com') }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-IntraOrganizationConnector {
            [pscustomobject]@{ Name = 'HybridIOC'; Enabled = $true; DiscoveryEndpoint = 'https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc' }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudOnPremisesOrganization {
            [pscustomobject]@{ Name = 'contoso-onprem'; HybridDomains = @('contoso.com'); InboundConnector = 'Inbound from contoso'; OutboundConnector = 'Outbound to contoso' }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudOrganizationRelationship { [pscustomobject]@{ Name = 'O365 to On-premises'; Enabled = $true; FreeBusyAccessEnabled = $true } }
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudIntraOrganizationConnector { [pscustomobject]@{ Name = 'HybridIOC'; Enabled = $false; DiscoveryEndpoint = 'https://mail.contoso.com/autodiscover/autodiscover.svc' } }
        $script:R = Test-EhcHybridConfiguration
    }

    It 'passes when the hybrid configuration exists' {
        ($script:R | Where-Object { $_.Check -eq 'Hybrid configuration object' }).Status | Should -Be 'Pass'
    }

    It 'finds the hybrid TLS certificate on servers that have it and fails where it is missing' {
        ($script:R | Where-Object { $_.Check -eq 'Hybrid TLS certificate' -and $_.Target -eq 'EX01' }).Status | Should -Be 'Pass'
        ($script:R | Where-Object { $_.Check -eq 'Hybrid TLS certificate' -and $_.Target -eq 'EX02' }).Status | Should -Be 'Fail'
    }

    It 'warns when free/busy sharing is disabled' {
        ($script:R | Where-Object { $_.Check -eq 'Organization relationship' -and $_.Target -like 'On-premises*' }).Status | Should -Be 'Warning'
    }

    It 'fails when the cloud OAuth connector is disabled' {
        ($script:R | Where-Object { $_.Check -like 'OAuth*' -and $_.Target -like 'Exchange Online*' }).Status | Should -Be 'Fail'
    }

    It 'fails when no hybrid configuration exists' {
        Mock -ModuleName ExchangeHybridHealthCheck Get-HybridConfiguration { }
        (Test-EhcHybridConfiguration | Where-Object { $_.Check -eq 'Hybrid configuration object' -and $_.Target -eq 'On-premises' }).Status | Should -Be 'Fail'
    }

    It 'honors a custom Exchange Online prefix' {
        $r = Test-EhcHybridConfiguration -CloudPrefix 'Exo'
        ($r | Where-Object { $_.Target -eq 'Exchange Online' }).Status | Should -Be 'Skipped'
    }
}

Describe 'Test-EhcConnector' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Get-SendConnector {
            [pscustomobject]@{ Name = 'Outbound to Office 365 - 1234'; AddressSpaces = @('smtp:contoso.mail.onmicrosoft.com;1'); Enabled = $true; RequireTLS = $true; TlsAuthLevel = 'DomainValidation'; TlsDomain = 'mail.protection.outlook.com'; TlsCertificateName = '<I>CA<S>CN=mail.contoso.com' }
            [pscustomobject]@{ Name = 'Internet'; AddressSpaces = @('smtp:*;1'); Enabled = $true; RequireTLS = $false; TlsAuthLevel = $null; TlsDomain = $null; TlsCertificateName = $null }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-ReceiveConnector {
            [pscustomobject]@{ Name = 'Default Frontend EX01'; Identity = 'EX01\Default Frontend EX01'; TlsCertificateName = '<I>CA<S>CN=mail.contoso.com' }
            [pscustomobject]@{ Name = 'Default Frontend EX02'; Identity = 'EX02\Default Frontend EX02'; TlsCertificateName = $null }
            [pscustomobject]@{ Name = 'Client Proxy EX01'; Identity = 'EX01\Client Proxy EX01'; TlsCertificateName = $null }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudInboundConnector {
            [pscustomobject]@{ Name = 'Inbound from contoso'; ConnectorType = 'OnPremises'; Enabled = $true; RequireTls = $true; TlsSenderCertificateName = 'mail.contoso.com' }
            [pscustomobject]@{ Name = 'Partner'; ConnectorType = 'Partner'; Enabled = $false; RequireTls = $false; TlsSenderCertificateName = $null }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudOutboundConnector {
            [pscustomobject]@{ Name = 'Outbound to contoso'; ConnectorType = 'OnPremises'; Enabled = $true; SmartHosts = @(); TlsSettings = 'DomainValidation' }
        }
        $script:R = Test-EhcConnector
    }

    It 'passes a correctly configured hybrid send connector and ignores the internet connector' {
        $send = @($script:R | Where-Object Check -EQ 'Send connector to Exchange Online')
        $send.Count | Should -Be 1
        $send[0].Status | Should -Be 'Pass'
    }

    It 'warns on a Default Frontend connector without a TLS certificate' {
        ($script:R | Where-Object Target -Like '*Default Frontend EX02').Status | Should -Be 'Warning'
        ($script:R | Where-Object Target -Like '*Client Proxy*') | Should -BeNullOrEmpty
    }

    It 'only evaluates OnPremises connectors in Exchange Online' {
        ($script:R | Where-Object Check -EQ 'Inbound connector from on-premises').Status | Should -Be 'Pass'
    }

    It 'fails an outbound connector with no smart hosts' {
        ($script:R | Where-Object Check -EQ 'Outbound connector to on-premises').Status | Should -Be 'Fail'
    }

    It 'fails when no hybrid send connector exists' {
        Mock -ModuleName ExchangeHybridHealthCheck Get-SendConnector { }
        (Test-EhcConnector | Where-Object Check -EQ 'Send connector to Exchange Online').Status | Should -Be 'Fail'
    }
}

Describe 'Test-EhcMigrationBatch' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudMigrationBatch {
            [pscustomobject]@{ Identity = 'Wave1-Partners'; Status = 'Completed'; TotalCount = 40; SyncedCount = 0; FinalizedCount = 40; FailedCount = 0; LastSyncedDateTime = $script:Now.AddDays(-10) }
            [pscustomobject]@{ Identity = 'Wave2-Associates'; Status = 'Synced'; TotalCount = 60; SyncedCount = 58; FinalizedCount = 0; FailedCount = 2; LastSyncedDateTime = $script:Now.AddHours(-2) }
            [pscustomobject]@{ Identity = 'Wave3-Staff'; Status = 'Failed'; TotalCount = 10; SyncedCount = 0; FinalizedCount = 0; FailedCount = 10; LastSyncedDateTime = $null }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudMigrationUser {
            [pscustomobject]@{ Identity = 'user1@contoso.com'; ErrorSummary = 'TooManyBadItemsPermanentException' }
        }
    }

    It 'rates batches by status and failure count' {
        $r = Test-EhcMigrationBatch
        ($r | Where-Object Target -EQ 'Wave1-Partners').Status | Should -Be 'Pass'
        ($r | Where-Object Target -EQ 'Wave2-Associates').Status | Should -Be 'Warning'
        ($r | Where-Object Target -EQ 'Wave3-Staff').Status | Should -Be 'Fail'
    }

    It 'lists failed users with -IncludeFailedUser' {
        $r = Test-EhcMigrationBatch -IncludeFailedUser
        @($r | Where-Object Check -EQ 'Failed migration user').Count | Should -Be 2
        Should -Invoke -ModuleName ExchangeHybridHealthCheck Get-CloudMigrationUser -ParameterFilter { $BatchId -eq 'Wave3-Staff' -and $Status -eq 'Failed' }
    }

    It 'returns Info when there are no batches' {
        Mock -ModuleName ExchangeHybridHealthCheck Get-CloudMigrationBatch { }
        (Test-EhcMigrationBatch).Status | Should -Be 'Info'
    }
}

Describe 'Test-EhcTransportQueue' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Get-Queue -ParameterFilter { $Server -eq 'EX01' } {
            [pscustomobject]@{ Identity = 'EX01\Submission'; MessageCount = 3; Status = 'Ready'; NextHopDomain = 'Submission'; DeliveryType = 'Undefined'; LastError = $null }
            [pscustomobject]@{ Identity = 'EX01\Poison'; MessageCount = 0; Status = 'Ready'; NextHopDomain = 'Poison Message'; DeliveryType = 'Undefined'; LastError = $null }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-Queue -ParameterFilter { $Server -eq 'EX02' } {
            [pscustomobject]@{ Identity = 'EX02\1234'; MessageCount = 250; Status = 'Retry'; NextHopDomain = 'contoso.mail.onmicrosoft.com'; DeliveryType = 'SmartHostConnectorDelivery'; LastError = '451 4.4.0 Primary target IP address responded with: 421 4.4.2 Connection dropped' }
            [pscustomobject]@{ Identity = 'EX02\Poison'; MessageCount = 2; Status = 'Ready'; NextHopDomain = 'Poison Message'; DeliveryType = 'Undefined'; LastError = $null }
            [pscustomobject]@{ Identity = 'EX02\5678'; MessageCount = 1500; Status = 'Active'; NextHopDomain = 'fabrikam.com'; DeliveryType = 'DnsConnectorDelivery'; LastError = $null }
        }
    }

    It 'returns a single Pass for a healthy server' {
        $r = @(Test-EhcTransportQueue -Server 'EX01')
        $r.Count | Should -Be 1
        $r[0].Status | Should -Be 'Pass'
    }

    It 'flags retry, poison, and oversized queues' {
        $r = Test-EhcTransportQueue -Server 'EX02'
        ($r | Where-Object Target -EQ 'EX02\1234').Status | Should -Be 'Warning'
        ($r | Where-Object Target -EQ 'EX02\1234').Detail | Should -Match 'Last error: 451'
        ($r | Where-Object Target -EQ 'EX02\Poison').Status | Should -Be 'Warning'
        ($r | Where-Object Target -EQ 'EX02\5678').Status | Should -Be 'Fail'
    }
}

Describe 'Test-EhcDatabaseHealth' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Get-MailboxDatabase {
            [pscustomobject]@{ Name = 'DB01'; Server = 'EX01'; Mounted = $true; DatabaseSize = '210 GB'; LastFullBackup = $script:Now.AddHours(-20); LastIncrementalBackup = $script:Now.AddHours(-4) }
            [pscustomobject]@{ Name = 'DB02'; Server = 'EX02'; Mounted = $false; DatabaseSize = '180 GB'; LastFullBackup = $script:Now.AddDays(-5); LastIncrementalBackup = $null }
            [pscustomobject]@{ Name = 'DB03'; Server = 'EX02'; Mounted = $true; DatabaseSize = '10 GB'; LastFullBackup = $null; LastIncrementalBackup = $null }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-DatabaseAvailabilityGroup { [pscustomobject]@{ Name = 'DAG01'; Servers = @('EX01', 'EX02') } }
        Mock -ModuleName ExchangeHybridHealthCheck Get-MailboxDatabaseCopyStatus -ParameterFilter { $Server -eq 'EX01' } {
            [pscustomobject]@{ Name = 'DB01\EX01'; Status = 'Mounted'; CopyQueueLength = 0; ReplayQueueLength = 0; ContentIndexState = 'Healthy' }
            [pscustomobject]@{ Name = 'DB02\EX01'; Status = 'Healthy'; CopyQueueLength = 25; ReplayQueueLength = 0; ContentIndexState = 'Healthy' }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Get-MailboxDatabaseCopyStatus -ParameterFilter { $Server -eq 'EX02' } {
            [pscustomobject]@{ Name = 'DB01\EX02'; Status = 'FailedAndSuspended'; CopyQueueLength = 0; ReplayQueueLength = 0; ContentIndexState = 'Failed' }
        }
        $script:R = Test-EhcDatabaseHealth
    }

    It 'fails dismounted databases' {
        ($script:R | Where-Object { $_.Check -eq 'Database mounted' -and $_.Target -eq 'DB02' }).Status | Should -Be 'Fail'
        ($script:R | Where-Object { $_.Check -eq 'Database mounted' -and $_.Target -eq 'DB01' }).Status | Should -Be 'Pass'
    }

    It 'checks backup recency using the newest full or incremental backup' {
        ($script:R | Where-Object { $_.Check -eq 'Backup recency' -and $_.Target -eq 'DB01' }).Status | Should -Be 'Pass'
        ($script:R | Where-Object { $_.Check -eq 'Backup recency' -and $_.Target -eq 'DB02' }).Status | Should -Be 'Warning'
        ($script:R | Where-Object { $_.Check -eq 'Backup recency' -and $_.Target -eq 'DB03' }).Detail | Should -Match 'No backup recorded'
    }

    It 'rates DAG copies' {
        ($script:R | Where-Object Target -EQ 'DB01\EX01').Status | Should -Be 'Pass'
        ($script:R | Where-Object Target -EQ 'DB02\EX01').Status | Should -Be 'Warning'
        ($script:R | Where-Object Target -EQ 'DB01\EX02').Status | Should -Be 'Fail'
    }

    It 'reports Info when there is no DAG' {
        Mock -ModuleName ExchangeHybridHealthCheck Get-DatabaseAvailabilityGroup { }
        (Test-EhcDatabaseHealth | Where-Object Check -EQ 'DAG copy status').Status | Should -Be 'Info'
    }
}

Describe 'Test-EhcServiceHealth' {
    It 'passes when all services run and fails with the stopped list otherwise' {
        Mock -ModuleName ExchangeHybridHealthCheck Test-ServiceHealth -ParameterFilter { $Server -eq 'EX01' } {
            [pscustomobject]@{ Role = 'Mailbox Server Role'; RequiredServicesRunning = $true; ServicesNotRunning = @() }
        }
        Mock -ModuleName ExchangeHybridHealthCheck Test-ServiceHealth -ParameterFilter { $Server -eq 'EX02' } {
            [pscustomobject]@{ Role = 'Mailbox Server Role'; RequiredServicesRunning = $false; ServicesNotRunning = @('MSExchangeTransport', 'MSExchangeFrontEndTransport') }
        }
        $r = Test-EhcServiceHealth -Server 'EX01', 'EX02'
        ($r | Where-Object Target -EQ 'EX01').Status | Should -Be 'Pass'
        ($r | Where-Object Target -EQ 'EX02').Status | Should -Be 'Fail'
        ($r | Where-Object Target -EQ 'EX02').Detail | Should -Match 'MSExchangeTransport'
    }
}

Describe 'Invoke-EhcHealthCheck' {
    BeforeAll {
        Mock -ModuleName ExchangeHybridHealthCheck Test-EhcCertificate { [pscustomobject]@{ PSTypeName = 'Ehc.Result'; Category = 'Certificates'; Check = 'Certificate expiry'; Target = 'EX01'; Status = 'Warning'; Detail = 'expires soon'; Timestamp = Get-Date } }
        Mock -ModuleName ExchangeHybridHealthCheck Test-EhcConnector { throw 'Simulated failure' }
        Mock -ModuleName ExchangeHybridHealthCheck Test-EhcServiceHealth { [pscustomobject]@{ PSTypeName = 'Ehc.Result'; Category = 'Services'; Check = 'Required services'; Target = 'EX01'; Status = 'Pass'; Detail = 'ok'; Timestamp = Get-Date } }
        $script:Out = Join-Path -Path $TestDrive -ChildPath 'ehc'
        $script:R = Invoke-EhcHealthCheck -Check Certificate, Connector, Service -OutputPath $script:Out
    }

    It 'runs only the selected checks' {
        Should -Invoke -ModuleName ExchangeHybridHealthCheck Test-EhcCertificate -Times 1 -Exactly -Scope Describe
        @($script:R).Count | Should -Be 3
    }

    It 'turns a check that throws into a Fail result and keeps going' {
        ($script:R | Where-Object Category -EQ 'Mail flow connectors').Status | Should -Be 'Fail'
        ($script:R | Where-Object Category -EQ 'Services').Status | Should -Be 'Pass'
    }

    It 'writes HTML, CSV, JSON, and a log' {
        foreach ($f in 'index.html', 'results.csv', 'results.json', 'run.log') {
            Test-Path -Path (Join-Path -Path $script:Out -ChildPath $f) | Should -BeTrue
        }
        $html = Get-Content -Path (Join-Path -Path $script:Out -ChildPath 'index.html') -Raw
        $html | Should -Match 'Overall: Action required'
        (Get-Content -Path (Join-Path -Path $script:Out -ChildPath 'results.json') -Raw | ConvertFrom-Json).Count | Should -Be 3
    }

    It 'writes nothing with -NoReport' {
        $out = Join-Path -Path $TestDrive -ChildPath 'none'
        $null = Invoke-EhcHealthCheck -Check Service -OutputPath $out -NoReport
        Test-Path -Path $out | Should -BeFalse
    }
}

Describe 'Export-EhcHtmlReport' {
    It 'HTML-encodes values and reports Healthy when everything passes' {
        $r = [pscustomobject]@{ Category = 'Test'; Check = '<b>x</b>'; Target = 't'; Status = 'Pass'; Detail = '<script>alert(1)</script>'; Timestamp = Get-Date }
        $file = $r | Export-EhcHtmlReport -Path (Join-Path -Path $TestDrive -ChildPath 'r.html')
        $html = Get-Content -Path $file.FullName -Raw
        $html | Should -Match 'Overall: Healthy'
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;alert'
    }
}
