function Resolve-DeviceLifecycleApiConfig {
    <#
    .SYNOPSIS
        Resolves organization-specific defaults for DeviceLifecycle-API.

    .DESCRIPTION
        DeviceLifecycle-API is an optional, read-only extension of the
        DeviceLifecycle repository. This function derives installation paths,
        runtime paths, task names and firewall rule names from OrganizationName.
        Explicit values in the configuration file always take precedence.
    #>

    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $organizationName = ([string]$Config.OrganizationName).Trim()
    if ([string]::IsNullOrWhiteSpace($organizationName)) {
        throw 'OrganizationName cannot be empty.'
    }

    if ($organizationName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw 'OrganizationName contains characters that are invalid in Windows paths.'
    }

    $Config.OrganizationName = $organizationName

    if ([string]::IsNullOrWhiteSpace([string]$Config.DataRoot)) {
        $Config.DataRoot = "C:\ProgramData\$organizationName\DeviceLifecycle"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Config.InstallRoot)) {
        $Config.InstallRoot = "C:\Program Files\$organizationName\DeviceLifecycle-API"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Config.ConfigRoot)) {
        $Config.ConfigRoot = "C:\ProgramData\$organizationName\DeviceLifecycleApi"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Config.TaskName)) {
        $Config.TaskName = "$organizationName - Device Lifecycle API"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Config.FirewallRuleName)) {
        $Config.FirewallRuleName = "$organizationName - Device Lifecycle API"
    }

    return $Config
}
