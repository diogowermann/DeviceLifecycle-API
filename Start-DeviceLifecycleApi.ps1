#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallRoot = $PSScriptRoot,

    [Parameter()]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = [Environment]::GetEnvironmentVariable('DEVICE_LIFECYCLE_API_CONFIG', 'Machine')
}

$pythonPath = Join-Path $InstallRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) {
    throw "Virtual environment Python was not found: $pythonPath"
}
if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath)) {
    throw "API configuration file was not found: $ConfigPath"
}

$apiKey = [Environment]::GetEnvironmentVariable('DEVICE_LIFECYCLE_API_KEY', 'Machine')
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'Machine environment variable DEVICE_LIFECYCLE_API_KEY is not configured.'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$env:DEVICE_LIFECYCLE_API_KEY = $apiKey
$env:DEVICE_LIFECYCLE_API_CONFIG = $ConfigPath

Set-Location -LiteralPath $InstallRoot

& $pythonPath `
    -m uvicorn `
    app.main:app `
    --host ([string]$config.listenAddress) `
    --port ([int]$config.port) `
    --workers 1 `
    --no-access-log

exit $LASTEXITCODE
