// SwitchBot公式CLI(switchbot-openapi-cli)のMCPサーバモードをAzure Container Appsでホストする
// ローカルで screen 等を使い起動しっぱなしにする運用の手間を無くすのが目的
@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('コンテナイメージ(例: ghcr.io/<user>/switchbot-mcp:latest)')
param containerImage string

@description('SwitchBot API のトークン(SwitchBotアプリ > プロフィール > 詳細設定 > 開発者向けオプション で取得)')
@secure()
param switchbotToken string

@description('SwitchBot API のシークレット')
@secure()
param switchbotSecret string

@description('MCPエンドポイント自体を守るBearerトークン。物理デバイスを操作できるため必須')
@secure()
param mcpBearerToken string

@description('コンテナイメージのpullに使うGHCRのユーザー名。イメージをpublicにする場合は空のままでよい')
param registryUsername string = ''

@description('コンテナイメージのpullに使うGHCRのトークン(read:packages権限)。イメージをpublicにする場合は空のままでよい')
@secure()
param registryPassword string = ''

@description('接続元IPをCIDR形式で制限する場合に指定(例: ["203.0.113.4/32"])。Bearerトークン認証への多層防御。空配列なら制限しない')
param allowedIpRanges array = []

var appName = 'switchbot-mcp'
var usePrivateRegistry = !empty(registryUsername)

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${appName}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource caEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${appName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    environmentId: caEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        ipSecurityRestrictions: [for (ip, i) in allowedIpRanges: {
          name: 'allow-${i}'
          description: 'Allowed IP range'
          ipAddressRange: ip
          action: 'Allow'
        }]
      }
      secrets: concat([
        {
          name: 'switchbot-token'
          value: switchbotToken
        }
        {
          name: 'switchbot-secret'
          value: switchbotSecret
        }
        {
          name: 'mcp-bearer-token'
          value: mcpBearerToken
        }
      ], usePrivateRegistry ? [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ] : [])
      registries: usePrivateRegistry ? [
        {
          server: 'ghcr.io'
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: appName
          image: containerImage
          env: [
            {
              name: 'SWITCHBOT_TOKEN'
              secretRef: 'switchbot-token'
            }
            {
              name: 'SWITCHBOT_SECRET'
              secretRef: 'switchbot-secret'
            }
            {
              name: 'SWITCHBOT_MCP_TOKEN'
              secretRef: 'mcp-bearer-token'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      // 呼び出し頻度が低い個人利用前提。アイドル時はゼロスケール
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
    }
  }
}

output mcpEndpoint string = 'https://${containerApp.properties.configuration.ingress.fqdn}/mcp'
