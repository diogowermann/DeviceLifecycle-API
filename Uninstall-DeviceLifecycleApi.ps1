#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'DeviceLifecycleApi.Config.psd1'),

    [Parameter()]
    [switch]$RemoveConfiguration,

    [Parameter()]
    [switch]$RemoveApiKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file was not found: $ConfigPath"
}

Import-Module (Join-Path $PSScriptRoot 'DeviceLifecycleApi.Helpers.psm1') -Force
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$config = Resolve-DeviceLifecycleApiConfig -Config $config

$installRoot = [string]$config.InstallRoot
$configRoot = [string]$config.ConfigRoot
$taskName = [string]$config.TaskName
$firewallRuleName = [string]$config.FirewallRuleName

if ($PSCmdlet.ShouldProcess($taskName, 'Remove scheduled task')) {
    if ($null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

if ($PSCmdlet.ShouldProcess($firewallRuleName, 'Remove firewall rule')) {
    Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

if ($PSCmdlet.ShouldProcess($installRoot, 'Remove API installation directory')) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($RemoveConfiguration -and $PSCmdlet.ShouldProcess($configRoot, 'Remove API runtime configuration and API logs')) {
    Remove-Item -LiteralPath $configRoot -Recurse -Force -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('DEVICE_LIFECYCLE_API_CONFIG', $null, 'Machine')
}

if ($RemoveApiKey -and $PSCmdlet.ShouldProcess('DEVICE_LIFECYCLE_API_KEY', 'Remove machine environment variable')) {
    [Environment]::SetEnvironmentVariable('DEVICE_LIFECYCLE_API_KEY', $null, 'Machine')
}

Write-Host 'DeviceLifecycle-API removed.' -ForegroundColor Green
Write-Host 'The DeviceLifecycle repository data, reports, logs and state were not removed.'
