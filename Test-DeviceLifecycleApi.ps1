#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = [Environment]::GetEnvironmentVariable('DEVICE_LIFECYCLE_API_CONFIG', 'Machine')
}

$results = New-Object System.Collections.ArrayList

function Add-TestResult {
    param(
        [string]$Test,
        [bool]$Success,
        [string]$Detail
    )

    [void]$results.Add([pscustomobject]@{
        Test = $Test
        Success = $Success
        Detail = $Detail
    })
}

try {
    $exists = -not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)
    Add-TestResult -Test 'Runtime configuration' -Success $exists -Detail ([string]$ConfigPath)

    if (-not $exists) {
        throw "Configuration file was not found: $ConfigPath"
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $apiKey = [Environment]::GetEnvironmentVariable('DEVICE_LIFECYCLE_API_KEY', 'Machine')
    $hasKey = -not [string]::IsNullOrWhiteSpace($apiKey)
    Add-TestResult -Test 'API key' -Success $hasKey -Detail 'Machine environment variable'

    $reportPath = Join-Path ([string]$config.dataRoot) ([string]$config.reportRelativePath)
    $reportExists = Test-Path -LiteralPath $reportPath
    Add-TestResult -Test 'Latest report' -Success $reportExists -Detail $reportPath

    $logPath = Join-Path ([string]$config.dataRoot) ([string]$config.logDirectoryRelativePath)
    $logExists = @(
        Get-ChildItem -LiteralPath $logPath -Filter '*.log' -File -ErrorAction SilentlyContinue
    ).Count -gt 0
    Add-TestResult -Test 'Lifecycle logs' -Success $logExists -Detail $logPath

    $task = Get-ScheduledTask -TaskName ([string]$config.taskName) -ErrorAction SilentlyContinue
    Add-TestResult `
        -Test 'Scheduled task' `
        -Success ($null -ne $task) `
        -Detail $(if ($null -ne $task) { [string]$task.State } else { 'Not found' })

    $baseUri = "http://localhost:$([int]$config.port)"
    $healthParameters = @{
        Uri = "$baseUri/api/v1/health"
        Method = 'Get'
        UseBasicParsing = $true
        TimeoutSec = 10
    }

    if ([bool]$config.healthRequiresAuthentication -and $hasKey) {
        $healthParameters.Headers = @{ 'X-API-Key' = $apiKey }
    }

    $health = Invoke-RestMethod @healthParameters
    Add-TestResult `
        -Test 'Health endpoint' `
        -Success ($health.status -eq 'ok' -and $health.extensionOf -eq 'DeviceLifecycle') `
        -Detail "$baseUri/api/v1/health"

    if ($hasKey) {
        $headers = @{ 'X-API-Key' = $apiKey }

        try {
            $metadata = Invoke-RestMethod `
                -Uri "$baseUri/api/v1/metadata" `
                -Headers $headers `
                -Method Get `
                -UseBasicParsing `
                -TimeoutSec 10

            Add-TestResult `
                -Test 'Authenticated metadata' `
                -Success ($metadata.readOnly -eq $true) `
                -Detail "API version $($metadata.apiVersion)"
        }
        catch {
            Add-TestResult -Test 'Authenticated metadata' -Success $false -Detail $_.Exception.Message
        }

        try {
            $response = Invoke-WebRequest `
                -Uri "$baseUri/api/v1/report.csv" `
                -Headers $headers `
                -Method Get `
                -UseBasicParsing `
                -TimeoutSec 10

            Add-TestResult `
                -Test 'Raw CSV endpoint' `
                -Success ($response.StatusCode -eq 200) `
                -Detail "$($response.RawContentLength) bytes"
        }
        catch {
            Add-TestResult -Test 'Raw CSV endpoint' -Success $false -Detail $_.Exception.Message
        }

        try {
            $response = Invoke-WebRequest `
                -Uri "$baseUri/api/v1/log?lines=20" `
                -Headers $headers `
                -Method Get `
                -UseBasicParsing `
                -TimeoutSec 10

            Add-TestResult `
                -Test 'Raw log endpoint' `
                -Success ($response.StatusCode -eq 200) `
                -Detail ([string]$response.Headers['X-Log-File'])
        }
        catch {
            Add-TestResult -Test 'Raw log endpoint' -Success $false -Detail $_.Exception.Message
        }
    }
}
catch {
    Add-TestResult -Test 'Fatal test error' -Success $false -Detail $_.Exception.Message
}

$results | Format-Table -AutoSize

if (@($results | Where-Object { -not $_.Success }).Count -gt 0) {
    exit 1
}

exit 0
