@description('The location into which your Azure resources should be deployed.')
param location string = resourceGroup().location

@description('choose a suitable environment name')
@allowed([
  'wip'
  'test'
  'qa'
  'prod'
])
param environment string

@description('choose a suitable customer prefix name')
@maxLength(5)
param customerPrefix string

@description('choose a suitable workload name')
@maxLength(5)
param workload string

@description('choose a suitable instance number. normally this will be 01 unless a duplicate is needed')
@maxLength(2)
param instance string = '01'

@description('OPTIONAL - choose a suitable component function')
param componentFunction string = ''

@description('The URL to the product review API.')
param reviewApiUrl string

@secure()
@description('The API key to use when accessing the product review API.')
param reviewApiKey string

@description('The administrator login username for the SQL server.')
param sqlServerAdministratorLogin string

@secure()
@description('The administrator login password for the SQL server.')
param sqlServerAdministratorLoginPassword string

// Define the names for resources.
var appServiceAppName = length(componentFunction) >= 1 ? 'app-${customerPrefix}${workload}${environment}${instance}${componentFunction}' : 'app-${customerPrefix}${workload}${environment}${instance}'
var appServicePlanName = length(componentFunction) >= 1 ? 'asp-${customerPrefix}${workload}${environment}${instance}${componentFunction}' : 'asp-${customerPrefix}${workload}${environment}${instance}'
var applicationInsightsName = length(componentFunction) >= 1 ? 'appi-${customerPrefix}${workload}${environment}${instance}${componentFunction}' : 'appi-${customerPrefix}${workload}${environment}${instance}'
var storageAccountName = length(componentFunction) >= 1 ? 'st${customerPrefix}${workload}${environment}${instance}${componentFunction}' : 'st${customerPrefix}${workload}${environment}${instance}'
var storageAccountImagesBlobContainerName = 'toyimages'
var sqlServerName = length(componentFunction) >= 1 ? 'sql-${customerPrefix}${workload}${environment}${instance}${componentFunction}' : 'sql-${customerPrefix}${workload}${environment}${instance}'
var sqlDatabaseName = length(componentFunction) >= 1 ? 'db-${customerPrefix}${workload}${environment}${instance}${componentFunction}' : 'db-${customerPrefix}${workload}${environment}${instance}'

// Define the connection string to access Azure SQL.
var sqlDatabaseConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabase.name};Persist Security Info=False;User ID=${sqlServerAdministratorLogin};Password=${sqlServerAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// Define the SKUs for each component based on the environment type.
var environmentConfigurationMap = {
  Production: {
    appServicePlan: {
      sku: {
        name: 'S1'
        capacity: 1
      }
    }
    storageAccount: {
      sku: {
        name: 'Standard_LRS'
      }
    }
    sqlDatabase: {
      sku: {
        name: 'Standard'
        tier: 'Standard'
      }
    }
  }
  Test: {
    appServicePlan: {
      sku: {
        name: 'F1'
      }
    }
    storageAccount: {
      sku: {
        name: 'Standard_LRS'
      }
    }
    sqlDatabase: {
      sku: {
        name: 'Standard'
        tier: 'Standard'
      }
    }
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2021-01-15' = {
  name: appServicePlanName
  location: location
  sku: environmentConfigurationMap[environment].appServicePlan.sku
}

resource appServiceApp 'Microsoft.Web/sites@2021-01-15' = {
  name: appServiceAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'ReviewApiUrl'
          value: reviewApiUrl
        }
        {
          name: 'ReviewApiKey'
          value: reviewApiKey
        }
        {
          name: 'StorageAccountName'
          value: storageAccount.name
        }
        {
          name: 'StorageAccountBlobEndpoint'
          value: storageAccount.properties.primaryEndpoints.blob
        }
        {
          name: 'StorageAccountImagesContainerName'
          value: storageAccount::blobService::storageAccountImagesBlobContainer.name
        }
        {
          name: 'SqlDatabaseConnectionString'
          value: sqlDatabaseConnectionString
        }
      ]
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    Flow_Type: 'Bluefield'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: environmentConfigurationMap[environment].storageAccount.sku

  resource blobService 'blobServices' = {
    name: 'default'

    resource storageAccountImagesBlobContainer 'containers' = {
      name: storageAccountImagesBlobContainerName

      properties: {
        publicAccess: 'Blob'
      }
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2021-02-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlServerAdministratorLogin
    administratorLoginPassword: sqlServerAdministratorLoginPassword
  }
}

resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2021-02-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: environmentConfigurationMap[environment].sqlDatabase.sku
}

output appServiceAppName string = appServiceApp.name
output appServiceAppHostName string = appServiceApp.properties.defaultHostName
output storageAccountName string = storageAccount.name
output storageAccountImagesBlobContainerName string = storageAccount::blobService::storageAccountImagesBlobContainer.name
output sqlServerFullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
