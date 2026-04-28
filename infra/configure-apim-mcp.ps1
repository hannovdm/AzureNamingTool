# Run AFTER the APIM Bicep deployment completes.
# Imports the Naming Tool OpenAPI spec and exposes it as an MCP server.

$ErrorActionPreference = 'Stop'

$SubscriptionId = 'ca8b8406-73fb-4b96-bee3-b7189f105c6c'
$ResourceGroup  = 'namingtool-rg'
$ApimName       = 'apim-namingtool-we'
# NOTE: $ApiId must match the existing API resource name in APIM. When the API
# was originally created through the portal "Import OpenAPI" wizard, APIM
# generated the id 'azure-naming-tool-api-v2' from the spec title. Keep this in
# sync with whatever name the API has in APIM.
$ApiId          = 'azure-naming-tool-api-v2'
$ApiPath        = 'namingtool'
$BackendBase    = 'https://namingtool-web-fwfzc0bzcrgghpdb.westeurope-01.azurewebsites.net'
$SwaggerUrl     = "$BackendBase/swagger/v2/swagger.json"

Write-Host "1. Waiting for APIM to be ready..." -ForegroundColor Cyan
do {
    $state = az apim show -n $ApimName -g $ResourceGroup --subscription $SubscriptionId --query provisioningState -o tsv 2>$null
    Write-Host "   state=$state"
    if ($state -eq 'Succeeded') { break }
    if ($state -eq 'Failed')    { throw 'APIM provisioning failed.' }
    Start-Sleep -Seconds 30
} while ($true)

Write-Host "2. Importing OpenAPI spec into APIM..." -ForegroundColor Cyan
az apim api import `
    --service-name $ApimName `
    --resource-group $ResourceGroup `
    --subscription $SubscriptionId `
    --api-id $ApiId `
    --path $ApiPath `
    --specification-format OpenApiJson `
    --specification-url $SwaggerUrl `
    --service-url $BackendBase `
    --display-name 'Azure Naming Tool' `
    --protocols https | Out-Null

Write-Host "2b. Ensuring path + serviceUrl are set on the API (PATCH)..." -ForegroundColor Cyan
# `az apim api import` does not always (re)apply --path / --service-url on an
# existing API. PATCH directly via ARM to guarantee both are set, otherwise
# APIM will return 404 for gateway calls and the MCP wrapper will return 500.
$apiPatchUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/$ApiId" + "?api-version=2024-05-01"
$apiPatchBody = @{ properties = @{ path = $ApiPath; serviceUrl = $BackendBase } } | ConvertTo-Json -Depth 5
$apiPatchBody | Set-Content -Path (Join-Path $env:TEMP 'namingtool-api-patch.json') -Encoding UTF8
az rest --method patch --uri $apiPatchUri `
    --headers "Content-Type=application/json" `
    --body "@$(Join-Path $env:TEMP 'namingtool-api-patch.json')" `
    --query "properties.{path:path,serviceUrl:serviceUrl}" -o json | Out-Null

Write-Host "3. Acquiring ARM access token..." -ForegroundColor Cyan
$token = az account get-access-token --subscription $SubscriptionId --query accessToken -o tsv

Write-Host "4. MCP exposure (manual step required)..." -ForegroundColor Cyan
# The "Expose REST API as MCP server" capability is only available through the
# Azure portal today. The public ARM REST API (Api_CreateOrUpdate) only supports
# wrapping an existing *external* MCP backend (serviceUrl + mcpProperties); it
# does not accept a `mcpTools` list referencing operations on a source REST API.
# Spec: https://github.com/Azure/azure-rest-api-specs/tree/main/specification/apimanagement/resource-manager/Microsoft.ApiManagement/ApiManagement/preview/2025-09-01-preview
$mcpManualSteps = @"
   --> Open the Azure portal:
       APIM ($ApimName) -> APIs -> 'Azure Naming Tool' -> ... menu ->
       'Expose as MCP server' -> select operations -> Create.
       Suggested MCP API path: $ApiPath-mcp
"@
Write-Host $mcpManualSteps -ForegroundColor Yellow

Write-Host "5. Ensuring 'namingtool-apikey' named value exists..." -ForegroundColor Cyan
$nvId = 'namingtool-apikey'
$nvExists = az apim nv show --service-name $ApimName -g $ResourceGroup --subscription $SubscriptionId --named-value-id $nvId -o tsv --query id 2>$null
if (-not $nvExists) {
    Write-Host "   Creating placeholder named value '$nvId' (secret)."
    az apim nv create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --subscription $SubscriptionId `
        --named-value-id $nvId `
        --display-name $nvId `
        --value '583ad564-6687-4246-acff-9dda7724d9e7' `
        --secret true | Out-Null
} else {
    Write-Host "   Named value '$nvId' already exists."
}

Write-Host "6. Applying API-level policy to inject APIKey header..." -ForegroundColor Cyan
$policyXml = @'
<policies>
  <inbound>
    <base />
    <set-header name="APIKey" exists-action="override">
      <value>{{namingtool-apikey}}</value>
    </set-header>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@
$policyFile = Join-Path $env:TEMP 'namingtool-policy.xml'
$policyXml | Set-Content -Path $policyFile -Encoding UTF8

$policyUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/apis/$ApiId/policies/policy?api-version=2024-05-01"
Invoke-RestMethod -Method Put -Uri $policyUri `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body (@{ properties = @{ format = 'xml'; value = $policyXml } } | ConvertTo-Json -Depth 5) | Out-Null

Write-Host "7. Getting gateway URL + subscription key..." -ForegroundColor Cyan
$gateway = az apim show -n $ApimName -g $ResourceGroup --subscription $SubscriptionId --query gatewayUrl -o tsv
$subKey  = az rest --method post `
    --uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/master/listSecrets?api-version=2024-05-01" `
    --query primaryKey -o tsv

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host "Gateway:  $gateway"
Write-Host "REST URL: $gateway/$ApiPath"
Write-Host "Sub key:  $subKey"
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Set the real downstream API key on the named value:"
Write-Host "     az apim nv update --service-name $ApimName -g $ResourceGroup --subscription $SubscriptionId --named-value-id namingtool-apikey --value '<YOUR_NAMING_TOOL_APIKEY>' --secret true"
Write-Host "  2. In the Azure portal, expose the API as an MCP server:"
Write-Host "     APIM -> APIs -> 'Azure Naming Tool' -> ... -> Expose as MCP server"
Write-Host "     After creation, the MCP endpoint will be: $gateway/$ApiPath-mcp/mcp"
