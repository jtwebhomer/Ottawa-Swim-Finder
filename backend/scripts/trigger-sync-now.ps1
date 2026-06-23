# Trigger sync via running API (POST /sync/run). API server must be up.
$ErrorActionPreference = 'Stop'
$BackendDir = Split-Path $PSScriptRoot -Parent
$EnvFile = Join-Path $BackendDir '.env'

$apiKey = ''
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^API_KEY=(.+)$') { $apiKey = $Matches[1].Trim() }
    }
}
if (-not $apiKey) { throw 'API_KEY not found in .env' }

$port = '3000'
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^PORT=(.+)$') { $port = $Matches[1].Trim() }
    }
}

$response = Invoke-RestMethod `
    -Uri "http://127.0.0.1:$port/sync/run" `
    -Method POST `
    -Headers @{ 'x-api-key' = $apiKey }

$response | ConvertTo-Json
Write-Host 'Sync started. Check status: GET /sync/status'
