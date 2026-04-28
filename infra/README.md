\infra\configure-apim-mcp.ps1                                               
1. Waiting for APIM to be ready...
   state=Succeeded
2. Importing OpenAPI spec into APIM...
3. Applying API-level policy to inject APIKey header...
4. Exposing API as an MCP server...
   MCP variant created.
5. Getting gateway URL + subscription key...

=== DONE ===
Gateway:  https://apim-namingtool-we.azure-api.net
REST URL: https://apim-namingtool-we.azure-api.net/namingtool
MCP URL:  https://apim-namingtool-we.azure-api.net/namingtool/mcp
Sub key:  fc46f175b2824fa1bdd64c6d7e5fea08

Naming tool 583ad564-6687-4246-acff-9dda7724d9e7

NEXT: set the real downstream API key:
  az apim nv update --service-name apim-namingtool-we -g namingtool-rg --subscription ca8b8406-73fb-4b96-bee3-b7189f105c6c --named-value-id namingtool-apikey --value '583ad564-6687-4246-acff-9dda7724d9e7' --secret true
ignore
  npx @modelcontextprotocol/inspector 
  
<policies>
	<inbound>
		<base />
		<set-header name="APIKey" exists-action="override">
			<value>{namingtool-apikey}</value>
		</set-header>
	</inbound>
	<backend>
		<base />
	</backend>
	<outbound>
		<base />
	</outbound>
	<on-error>
		<base />
	</on-error>
</policies>