#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'DeviceLifecycleApi.Config.psd1'),

    [Parameter()]
    [string[]]$RemoteAddress,

    [Parameter()]
    [string]$ApiKey,

    [Parameter()]
    [string]$PythonExecutable,

    [Parameter()]
    [switch]$HealthRequiresAuthentication,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SystemPython {
    param([string]$RequestedExecutable)

    if (-not [string]::IsNullOrWhiteSpace($RequestedExecutable)) {
        if (-not (Test-Path -LiteralPath $RequestedExecutable)) {
            throw "Python executable was not found: $RequestedExecutable"
        }

        return [pscustomobject]@{
            Executable = $RequestedExecutable
            Prefix = @()
        }
    }

    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $python) {
        return [pscustomobject]@{
            Executable = $python.Source
            Prefix = @()
        }
    }

    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($null -ne $launcher) {
        return [pscustomobject]@{
            Executable = $launcher.Source
            Prefix = @('-3')
        }
    }

    throw 'Python 3.10 or newer was not found. Install Python for all users or configure PythonExecutable.'
}

function Invoke-ResolvedPython {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Python,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    $allArguments = @($Python.Prefix) + @($Arguments)
    & $Python.Executable @allArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE."
    }
}

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

if ($PSBoundParameters.ContainsKey('RemoteAddress')) {
    $config.RemoteAddress = @($RemoteAddress)
}
if ($PSBoundParameters.ContainsKey('PythonExecutable')) {
    $config.PythonExecutable = $PythonExecutable
}
if ($PSBoundParameters.ContainsKey('HealthRequiresAuthentication')) {
    $config.HealthRequiresAuthentication = [bool]$HealthRequiresAuthentication
}

$installRoot = [string]$config.InstallRoot
$dataRoot = [string]$config.DataRoot
$configRoot = [string]$config.ConfigRoot
$taskName = [string]$config.TaskName
$firewallRuleName = [string]$config.FirewallRuleName
$listenAddress = [string]$config.ListenAddress
$port = [int]$config.Port
$maxLogLines = [int]$config.MaxLogLines
$allowedRemoteAddresses = @($config.RemoteAddress)
$runtimeConfigPath = Join-Path $configRoot 'Api.Config.json'
$apiLogDirectory = Join-Path $configRoot 'Logs'

if ($port -lt 1 -or $port -gt 65535) {
    throw 'Port must be between 1 and 65535.'
}
if ($maxLogLines -lt 1 -or $maxLogLines -gt 100000) {
    throw 'MaxLogLines must be between 1 and 100000.'
}
if (-not (Test-Path -LiteralPath $dataRoot)) {
    throw "DeviceLifecycle data directory was not found: $dataRoot"
}

$reportPath = Join-Path $dataRoot ([string]$config.ReportRelativePath)
$logDirectory = Join-Path $dataRoot ([string]$config.LogDirectoryRelativePath)

if (-not (Test-Path -LiteralPath $reportPath)) {
    throw "DeviceLifecycle latest report was not found: $reportPath"
}
if (-not (Test-Path -LiteralPath $logDirectory)) {
    throw "DeviceLifecycle log directory was not found: $logDirectory"
}

$python = Resolve-SystemPython -RequestedExecutable ([string]$config.PythonExecutable)
$versionText = & $python.Executable @($python.Prefix) -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to determine the installed Python version.'
}

$pythonVersion = [version]($versionText | Select-Object -Last 1)
if ($pythonVersion -lt [version]'3.10') {
    throw "Python 3.10 or newer is required. Found: $pythonVersion"
}

if ((Test-Path -LiteralPath $installRoot) -and -not $Force) {
    throw "Installation directory already exists. Use -Force to update it: $installRoot"
}

if ($PSCmdlet.ShouldProcess($installRoot, 'Install DeviceLifecycle-API')) {
    New-Item -Path $installRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $configRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $apiLogDirectory -ItemType Directory -Force | Out-Null

    Remove-Item -LiteralPath (Join-Path $installRoot 'app') -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'app') -Destination $installRoot -Recurse -Force

    foreach ($fileName in @(
        'requirements.txt',
        'DeviceLifecycleApi.Helpers.psm1',
        'Start-DeviceLifecycleApi.ps1',
        'Test-DeviceLifecycleApi.ps1',
        'Reset-DeviceLifecycleApiKey.ps1',
        'Uninstall-DeviceLifecycleApi.ps1',
        'README.md'
    )) {
        $sourcePath = Join-Path $PSScriptRoot $fileName
        $destinationPath = Join-Path $installRoot $fileName
        if ((Resolve-Path -LiteralPath $sourcePath).Path -ne $destinationPath) {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
    }

    $virtualEnvironment = Join-Path $installRoot '.venv'
    if (-not (Test-Path -LiteralPath $virtualEnvironment)) {
        Invoke-ResolvedPython -Python $python -Arguments @('-m', 'venv', $virtualEnvironment)
    }

    $venvPython = Join-Path $virtualEnvironment 'Scripts\python.exe'
    & $venvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to upgrade pip in the API virtual environment.'
    }

    & $venvPython -m pip install -r (Join-Path $installRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to install the API Python dependencies.'
    }

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $ApiKey = New-SecureApiKey
    }
    if ($ApiKey.Length -lt 32) {
        throw 'The API key must contain at least 32 characters.'
    }

    [Environment]::SetEnvironmentVariable('DEVICE_LIFECYCLE_API_KEY', $ApiKey, 'Machine')
    [Environment]::SetEnvironmentVariable('DEVICE_LIFECYCLE_API_CONFIG', $runtimeConfigPath, 'Machine')

    $runtimeConfiguration = [ordered]@{
        organizationName = [string]$config.OrganizationName
        sourceService = 'DeviceLifecycle'
        extensionName = 'DeviceLifecycle-API'
        dataRoot = $dataRoot
        reportRelativePath = [string]$config.ReportRelativePath
        logDirectoryRelativePath = [string]$config.LogDirectoryRelativePath
        apiLogDirectory = $apiLogDirectory
        taskName = $taskName
        listenAddress = $listenAddress
        port = $port
        maxLogLines = $maxLogLines
        healthRequiresAuthentication = [bool]$config.HealthRequiresAuthentication
    }

    $runtimeConfiguration |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $runtimeConfigPath -Encoding UTF8 -Force

    $installedConfigPath = Join-Path $installRoot 'DeviceLifecycleApi.Config.psd1'
    $resolvedSourceConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    $resolvedInstalledConfig = [IO.Path]::GetFullPath($installedConfigPath)
    if (-not $resolvedSourceConfig.Equals($resolvedInstalledConfig, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $resolvedSourceConfig -Destination $resolvedInstalledConfig -Force
    }

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $existingTask) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $startScript = Join-Path $installRoot 'Start-DeviceLifecycleApi.ps1'
    $taskArguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f $startScript),
        '-InstallRoot',
        ('"{0}"' -f $installRoot),
        '-ConfigPath',
        ('"{0}"' -f $runtimeConfigPath)
    ) -join ' '

    $action = New-ScheduledTaskAction -Execute $powershellPath -Argument $taskArguments -WorkingDirectory $installRoot
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 5 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Description 'Read-only HTTP extension for DeviceLifecycle reports and logs.' `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    if ($allowedRemoteAddresses.Count -gt 0) {
        New-NetFirewallRule `
            -DisplayName $firewallRuleName `
            -Description 'Allows approved servers to query the DeviceLifecycle read-only API.' `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $port `
            -Profile Domain `
            -RemoteAddress $allowedRemoteAddresses | Out-Null
    }

    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2

    Write-Host ''
    Write-Host 'DeviceLifecycle-API installed successfully.' -ForegroundColor Green
    Write-Host "Extension of : DeviceLifecycle"
    Write-Host "Install root : $installRoot"
    Write-Host "Config path  : $runtimeConfigPath"
    Write-Host "Local URL    : http://localhost:$port/api/v1/health"

    if ($allowedRemoteAddresses.Count -gt 0) {
        Write-Host "Allowed IPs  : $($allowedRemoteAddresses -join ', ')"
    }
    else {
        Write-Warning 'No inbound firewall rule was created. Remote access depends on existing firewall policy.'
    }

    Write-Host ''
    Write-Host 'API KEY - store this securely and do not commit it:' -ForegroundColor Yellow
    Write-Host $ApiKey
    Write-Host ''
    Write-Host "Run: & '$installRoot\Test-DeviceLifecycleApi.ps1'"
}
