# switchbot-mcp-container-apps

SwitchBot公式CLI（[switchbot-openapi-cli](https://github.com/OpenWonderLabs/switchbot-openapi-cli)）のMCPサーバモードを、Azure Container Apps でホストするサンプルです。

ローカルで動かす場合、`screen` や `tmux` で起動しっぱなしにする運用が地味に面倒だったため、Azureに任せて楽をするのが目的です。SwitchBotのCloud APIを呼ぶだけのステートレスな構成なので、永続化やロックの心配がありません。

🇺🇸 [English README](README.md)

## 提供ツール

CLIの `mcp serve` がデフォルトで17個のツール（`list_devices` / `get_device_status` / `send_command` 等）を公開します。全ツール一覧は以下で確認できます。

```bash
docker run --rm switchbot-mcp switchbot mcp tools
```

## 重要: このMCPサーバは物理デバイスを操作できます

`send_command` 経由で自宅の鍵・カーテン・プラグ等を実際に操作できてしまうため、**Bearerトークン認証は必須**です（`--bind 0.0.0.0` で起動する場合、CLI自体が認証必須を強制します）。

## ローカルで動かす（Docker）

```bash
docker build -t switchbot-mcp .

docker run -p 8080:8080 \
  -e SWITCHBOT_TOKEN=<SwitchBotアプリで発行したトークン> \
  -e SWITCHBOT_SECRET=<同シークレット> \
  -e SWITCHBOT_MCP_TOKEN=<このMCPサーバ自体を守る任意のBearerトークン> \
  switchbot-mcp
```

SwitchBotのトークン・シークレットは、SwitchBotアプリ > プロフィール > 設定 > 開発者向けオプション から取得します。

Claude Desktop の設定ファイルに追記します。

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

## Azure Container Apps にデプロイする（Bicep）

```bash
az group create --name rg-switchbot-mcp --location japaneast

az deployment group create \
  --resource-group rg-switchbot-mcp \
  --template-file infra/main.bicep \
  --parameters containerImage=ghcr.io/<your-github-user>/switchbot-mcp-container-apps:latest \
  --parameters switchbotToken=<token> switchbotSecret=<secret> mcpBearerToken=<任意の文字列>
```

デプロイ後、出力される `mcpEndpoint` を使って設定します。

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

アイドル時はゼロスケールする設定にしているため、個人利用の呼び出し頻度であればコストはごく小さい想定です（実測は別途記載予定）。

## 追加のセキュリティ強化(検討中)

CLI自体のBearerトークンに加えて、Container Apps組み込みのMicrosoft Entra ID認証を前段に重ねる二重防御も検討中です。

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

## 実機検証で分かったこと

- Web上の一部情報では `switchbot mcp serve --transport http --port <n>` という記法が紹介されていたが、実際にインストールされる `@switchbot/openapi-cli@3.8.1` にそのオプションは無く `unknown option '--transport'` でエラーになった。正しくは `--port <n>` を渡すだけでHTTPモードになり、外部公開時は `--bind 0.0.0.0` と `--auth-token`（または `SWITCHBOT_MCP_TOKEN` 環境変数）が必須
- 認証なしでのリクエストは `401` + JSON-RPCエラー `{"code":-32001,"message":"Unauthorized"}` で正しく弾かれることをローカルで確認済み

## 依存関係

- `@switchbot/openapi-cli` (npm)
- Node.js 22+
