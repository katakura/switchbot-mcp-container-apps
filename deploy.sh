#!/usr/bin/env bash
# SwitchBot MCPサーバをAzure Container Appsにデプロイし、実行時点の自宅グローバルIPだけに接続を絞る
# 使い方: SWITCHBOT_TOKEN=... SWITCHBOT_SECRET=... MCP_BEARER_TOKEN=... ./deploy.sh <resource-group> [location]
#
# 秘密情報はコマンドライン引数ではなく環境変数 + 一時パラメータファイル経由で渡す
# (シェル履歴やAzureのアクティビティログに生値が残らないようにするため)
set -euo pipefail

RESOURCE_GROUP="${1:?resource group name is required}"
LOCATION="${2:-japaneast}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-ghcr.io/katakura/switchbot-mcp-container-apps:latest}"

SWITCHBOT_TOKEN="${SWITCHBOT_TOKEN:?SWITCHBOT_TOKEN env var (SwitchBotアプリ > プロフィール > 開発者向けオプション で取得) is required}"
SWITCHBOT_SECRET="${SWITCHBOT_SECRET:?SWITCHBOT_SECRET env var is required}"
MCP_BEARER_TOKEN="${MCP_BEARER_TOKEN:?MCP_BEARER_TOKEN env var (MCPエンドポイント自体を守る任意のトークン。例: openssl rand -hex 16) is required}"

echo "自宅グローバルIPを取得中..."
# Container Apps の ipSecurityRestrictions は IPv4 のみ対応のため -4 で強制する
# (IPv6環境だと ifconfig.me がIPv6を返し、/32を付けても不正な値になる)
MY_IP="$(curl -4 -fsS https://ifconfig.me)"
echo "検出したIP: ${MY_IP} (${MY_IP}/32 のみ許可)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMS_FILE="$(mktemp)"
chmod 600 "$PARAMS_FILE"
trap 'rm -f "$PARAMS_FILE"' EXIT

cat > "$PARAMS_FILE" <<EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "containerImage": { "value": "${CONTAINER_IMAGE}" },
    "switchbotToken": { "value": "${SWITCHBOT_TOKEN}" },
    "switchbotSecret": { "value": "${SWITCHBOT_SECRET}" },
    "mcpBearerToken": { "value": "${MCP_BEARER_TOKEN}" },
    "allowedIpRanges": { "value": ["${MY_IP}/32"] }
  }
}
EOF

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none

echo "デプロイ中..."
ENDPOINT="$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "${SCRIPT_DIR}/infra/main.bicep" \
  --parameters "@${PARAMS_FILE}" \
  --query "properties.outputs.mcpEndpoint.value" -o tsv)"

echo "MCP endpoint: ${ENDPOINT}"
echo "許可IP: ${MY_IP}/32 (このIPが変わった場合は再実行してください)"
