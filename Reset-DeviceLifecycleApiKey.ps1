#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ApiKey,

    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'DeviceLifecycleApi.Config.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SecureApiKey {
    $bytes = New-Object byte[] 32
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file was not found: $ConfigPath"
}

Import-Module (Join-Path $PSScriptRoot 'DeviceLifecycleApi.Helpers.psm1') -Force
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$config = Resolve-DeviceLifecycleApiConfig -Config $config

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = New-SecureApiKey
}
if ($ApiKey.Length -lt 32) {
    throw 'The API key must contain at least 32 characters.'
}

[Environment]::SetEnvironmentVariable('DEVICE_LIFECYCLE_API_KEY', $ApiKey, 'Machine')

$taskName = [string]$config.TaskName
if ($null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName $taskName
}

Write-Host 'API key updated. Update all API consumers:' -ForegroundColor Yellow
Write-Host $ApiKey
