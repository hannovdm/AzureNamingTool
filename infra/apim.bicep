// Deploys Azure API Management (BasicV2) to front the Azure Naming Tool API
// and expose it as an MCP server for use from GitHub Copilot / VS Code.
//
// Deploy:
//   az deployment group create \
//     -g namingtool-rg \
//     --subscription ca8b8406-73fb-4b96-bee3-b7189f105c6c \
//     -f apim.bicep

@description('APIM instance name (globally unique).')
param apimName string = 'apim-namingtool-we'

@description('Region. Must be a region that supports the v2 SKU.')
param location string = resourceGroup().location

@description('Publisher email (shown on developer portal).')
param publisherEmail string = 'hannov@microsoft.com'

@description('Publisher organization name.')
param publisherName string = 'Microsoft'

@description('v2 SKU required for MCP server exposure.')
@allowed([
  'BasicV2'
  'StandardV2'
])
param skuName string = 'BasicV2'

@description('Public HTTPS base URL of the Naming Tool web app.')
param backendBaseUrl string = 'https://namingtool-web-fwfzc0bzcrgghpdb.westeurope-01.azurewebsites.net'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: skuName
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Named value holding the downstream APIKey that the Naming Tool expects on
// every request. Set the real value after deployment (portal or CLI):
//   az apim nv update --service-name apim-namingtool-we -g namingtool-rg \
//     --named-value-id namingtool-apikey --value '<YOUR_KEY>' --secret true
resource apiKeyNV 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'namingtool-apikey'
  properties: {
    displayName: 'namingtool-apikey'
    secret: true
    value: 'REPLACE_ME'
  }
}

output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output backendBaseUrl string = backendBaseUrl
