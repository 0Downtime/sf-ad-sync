Describe 'Get-SfAdSyncConfig' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../src/Modules/SfAdSync/Config.psm1" -Force
    }

    It 'loads the sample config successfully' {
        $configPath = Join-Path $PSScriptRoot '../config/sample.sync-config.json'
        $config = Get-SfAdSyncConfig -Path $configPath
        $config.successFactors.baseUrl | Should -Not -BeNullOrEmpty
        $config.ad.graveyardOu | Should -Not -BeNullOrEmpty
    }

    It 'prefers environment variables for secret values' {
        $configPath = Join-Path $TestDrive 'sync-config.json'
        @'
{
  "secrets": {
    "successFactorsClientIdEnv": "TEST_SF_CLIENT_ID",
    "successFactorsClientSecretEnv": "TEST_SF_CLIENT_SECRET",
    "defaultAdPasswordEnv": "TEST_AD_PASSWORD"
  },
  "successFactors": {
    "baseUrl": "https://example.successfactors.com/odata/v2",
    "oauth": {
      "tokenUrl": "https://example.successfactors.com/oauth/token",
      "clientId": "config-client-id",
      "clientSecret": "config-client-secret"
    },
    "query": {
      "entitySet": "PerPerson",
      "identityField": "personIdExternal",
      "deltaField": "lastModifiedDateTime",
      "select": [ "personIdExternal" ],
      "expand": [ "employmentNav" ]
    }
  },
  "ad": {
    "identityAttribute": "employeeID",
    "defaultActiveOu": "OU=Employees,DC=example,DC=com",
    "graveyardOu": "OU=Graveyard,DC=example,DC=com",
    "defaultPassword": "config-password"
  },
  "sync": {
    "enableBeforeStartDays": 7,
    "deletionRetentionDays": 90
  },
  "state": {
    "path": ".\\state\\sync-state.json"
  },
  "reporting": {
    "outputDirectory": ".\\reports\\output"
  }
}
'@ | Set-Content -Path $configPath

        [System.Environment]::SetEnvironmentVariable('TEST_SF_CLIENT_ID', 'env-client-id')
        [System.Environment]::SetEnvironmentVariable('TEST_SF_CLIENT_SECRET', 'env-client-secret')
        [System.Environment]::SetEnvironmentVariable('TEST_AD_PASSWORD', 'env-password')

        try {
            $config = Get-SfAdSyncConfig -Path $configPath
            $config.successFactors.oauth.clientId | Should -Be 'env-client-id'
            $config.successFactors.oauth.clientSecret | Should -Be 'env-client-secret'
            $config.ad.defaultPassword | Should -Be 'env-password'
        } finally {
            [System.Environment]::SetEnvironmentVariable('TEST_SF_CLIENT_ID', $null)
            [System.Environment]::SetEnvironmentVariable('TEST_SF_CLIENT_SECRET', $null)
            [System.Environment]::SetEnvironmentVariable('TEST_AD_PASSWORD', $null)
        }
    }

    It 'rejects config missing nested required values' {
        $configPath = Join-Path $TestDrive 'invalid-sync-config.json'
        @'
{
  "successFactors": {
    "baseUrl": "https://example.successfactors.com/odata/v2",
    "oauth": {
      "tokenUrl": "",
      "clientId": "client-id",
      "clientSecret": "client-secret"
    },
    "query": {
      "entitySet": "PerPerson",
      "identityField": "personIdExternal",
      "deltaField": "lastModifiedDateTime",
      "select": [ "personIdExternal" ],
      "expand": [ "employmentNav" ]
    }
  },
  "ad": {
    "identityAttribute": "employeeID",
    "defaultActiveOu": "OU=Employees,DC=example,DC=com",
    "graveyardOu": "OU=Graveyard,DC=example,DC=com",
    "defaultPassword": "password"
  },
  "sync": {
    "enableBeforeStartDays": 7,
    "deletionRetentionDays": 90
  },
  "state": {
    "path": ".\\state\\sync-state.json"
  },
  "reporting": {
    "outputDirectory": ".\\reports\\output"
  }
}
'@ | Set-Content -Path $configPath

        { Get-SfAdSyncConfig -Path $configPath } | Should -Throw '*successFactors.oauth.tokenUrl*'
    }
}

Describe 'Get-SfAdSyncMappingConfig' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../src/Modules/SfAdSync/Config.psm1" -Force
    }

    It 'rejects unsupported transforms' {
        $mappingPath = Join-Path $TestDrive 'invalid-mapping.json'
        @'
{
  "mappings": [
    {
      "source": "firstName",
      "target": "givenName",
      "enabled": true,
      "required": true,
      "transform": "SnakeCase"
    }
  ]
}
'@ | Set-Content -Path $mappingPath

        { Get-SfAdSyncMappingConfig -Path $mappingPath } | Should -Throw '*unsupported transform*'
    }
}
