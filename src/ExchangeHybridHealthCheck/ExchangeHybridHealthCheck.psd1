@{
    RootModule           = 'ExchangeHybridHealthCheck.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'b3d1c7e4-5a2f-4b8e-9f61-2c4d8e7a9b03'
    Author               = 'John Harrington'
    Copyright            = '(c) John Harrington. MIT License.'
    Description          = 'Read-only health check for Exchange Server 2016/2019 hybrid deployments with Exchange Online: certificates, hybrid configuration, connectors, migration batches, transport queues, DAG/database health, and services. Produces an HTML dashboard.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'Test-EhcCertificate'
        'Test-EhcHybridConfiguration'
        'Test-EhcConnector'
        'Test-EhcMigrationBatch'
        'Test-EhcTransportQueue'
        'Test-EhcDatabaseHealth'
        'Test-EhcServiceHealth'
        'Invoke-EhcHealthCheck'
        'Export-EhcHtmlReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Exchange', 'ExchangeOnline', 'Hybrid', 'HealthCheck', 'Microsoft365', 'Reporting')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
