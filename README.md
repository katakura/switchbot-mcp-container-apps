# switchbot-mcp-container-apps

A sample that hosts the MCP server mode of the official [SwitchBot CLI](https://github.com/OpenWonderLabs/switchbot-openapi-cli) (`switchbot-openapi-cli`) on Azure Container Apps.

Running it locally meant keeping a `screen`/`tmux` session alive, which got tedious. This offloads that to Azure instead. Since it's just a stateless proxy to the SwitchBot Cloud API, there's no persistence or locking to worry about.

🇯🇵 [日本語 README](README-ja.md)

## Tools

`mcp serve` exposes 17 tools by default (`list_devices`, `get_device_status`, `send_command`, etc.). List them all with:

```bash
docker run --rm switchbot-mcp switchbot mcp tools
```

## Important: this MCP server can control physical devices

`send_command` can actually operate your locks, curtains, plugs, etc., so **Bearer token authentication is mandatory**. The CLI itself enforces this when bound to `0.0.0.0`.

## Run locally (Docker)

```bash
docker build -t switchbot-mcp .

docker run -p 8080:8080 \
  -e SWITCHBOT_TOKEN=<token from the SwitchBot app> \
  -e SWITCHBOT_SECRET=<secret> \
  -e SWITCHBOT_MCP_TOKEN=<any bearer token to protect this server> \
  switchbot-mcp
```

Get your SwitchBot token/secret from the SwitchBot app under Profile > Settings > Developer Options.

Add to your Claude Desktop config:

```json
{
  "mcpServers": {
    "switchbot": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://localhost:8080/mcp",
        "--allow-http",
        "--header",
        "Authorization:Bearer ${SWITCHBOT_MCP_TOKEN}"
      ],
      "env": {
        "SWITCHBOT_MCP_TOKEN": "..."
      }
    }
  }
}
```

## Deploy to Azure Container Apps (Bicep)

```bash
az group create --name rg-switchbot-mcp --location japaneast

az deployment group create \
  --resource-group rg-switchbot-mcp \
  --template-file infra/main.bicep \
  --parameters containerImage=ghcr.io/<your-github-user>/switchbot-mcp-container-apps:latest \
  --parameters switchbotToken=<token> switchbotSecret=<secret> mcpBearerToken=<any string>
```

After deployment, use the `mcpEndpoint` output:

```json
{
  "mcpServers": {
    "switchbot": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "https://<your-endpoint>/mcp",
        "--header",
        "Authorization:Bearer ${SWITCHBOT_MCP_TOKEN}"
      ],
      "env": {
        "SWITCHBOT_MCP_TOKEN": "..."
      }
    }
  }
}
```

Scales to zero when idle, so cost should be minimal for personal-use call volume (actual measurement TBD).

## Additional hardening (under consideration)

Layering Container Apps' built-in Microsoft Entra ID authentication in front of the CLI's own Bearer token, as defense in depth:

```bash
az containerapp auth microsoft update \
  --name switchbot-mcp \
  --resource-group rg-switchbot-mcp \
  --client-id <app-id> \
  --client-secret <secret> \
  --tenant-id <tenant-id> \
  --issuer "https://login.microsoftonline.com/<tenant-id>/v2.0" \
  --yes

az containerapp auth update \
  --name switchbot-mcp \
  --resource-group rg-switchbot-mcp \
  --unauthenticated-client-action Return401
```

## Findings from real-world verification

- Some sources online reference `switchbot mcp serve --transport http --port <n>`, but the installed `@switchbot/openapi-cli@3.8.1` has no such flag (`unknown option '--transport'`). The correct usage is just `--port <n>` for HTTP mode; exposing it externally additionally requires `--bind 0.0.0.0` and `--auth-token` (or the `SWITCHBOT_MCP_TOKEN` env var)
- Verified locally that unauthenticated requests are correctly rejected with `401` and a JSON-RPC error `{"code":-32001,"message":"Unauthorized"}`

## Requirements

- `@switchbot/openapi-cli` (npm)
- Node.js 22+
