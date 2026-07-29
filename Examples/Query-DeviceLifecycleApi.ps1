#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$ApiKey,

    [Parameter()]
    [int]$Port = 8088
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseUri = "http://$Server`:$Port"
$headers = @{ 'X-API-Key' = $ApiKey }

Write-Host 'Health:' -ForegroundColor Cyan
Invoke-RestMethod -Uri "$baseUri/api/v1/health" -Method Get -UseBasicParsing

Write-Host ''
Write-Host 'Extension metadata:' -ForegroundColor Cyan
Invoke-RestMethod `
    -Uri "$baseUri/api/v1/metadata" `
    -Headers $headers `
    -Method Get `
    -UseBasicParsing

Write-Host ''
Write-Host 'First five report records:' -ForegroundColor Cyan
$report = Invoke-RestMethod `
    -Uri "$baseUri/api/v1/report" `
    -Headers $headers `
    -Method Get `
    -UseBasicParsing

$report.records | Select-Object -First 5 | Format-Table -AutoSize

Write-Host ''
Write-Host 'Last 20 DeviceLifecycle log lines:' -ForegroundColor Cyan
$response = Invoke-WebRequest `
    -Uri "$baseUri/api/v1/log?lines=20" `
    -Headers $headers `
    -Method Get `
    -UseBasicParsing

$response.Content
