<#
# =============================================================================
# README - Windows software installer
# =============================================================================
#
# Purpose
# -------
# Installs a personal list of Windows applications with winget.
#
# Default behavior
# ----------------
# - Uses `windows/private/windows_apps.psd1` as the default app list
# - Runs `install_system_requirements.ps1` when `winget` is not available
# - Prompts once for another `.psd1` file when the default app list is missing
# - Creates an empty app-list template when the prompt input is missing or invalid
# - Ignores empty app IDs and removes duplicates before installation
#
# App list structure
# ------------------
# The app list must be a PowerShell data file with this shape:
#
# @{
#     Apps = @(
#         "Vendor.App"
#     )
# }
#
# Example:
#   .\install_softwares.ps1
#
# Notes
# -----
# - This script is intended for Windows PowerShell or PowerShell on Windows
# - Keep `windows/private/windows_apps.psd1` out of source control
# - Internet access is required when system requirements must be installed first
#
# =============================================================================
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
# Section: Load helpers
# =============================================================================

$writeHelpersPath = Join-Path $PSScriptRoot "utils\write_helpers.ps1"
if (-not (Test-Path $writeHelpersPath -PathType Leaf)) {
    throw "Write helper functions not found at $writeHelpersPath"
}

. $writeHelpersPath

$systemHelpersPath = Join-Path $PSScriptRoot "utils\system_helpers.ps1"
if (-not (Test-Path $systemHelpersPath -PathType Leaf)) {
    throw "System helper functions not found at $systemHelpersPath"
}

. $systemHelpersPath

$bootstrapHelpersPath = Join-Path $PSScriptRoot "utils\bootstrap_helpers.ps1"
if (-not (Test-Path $bootstrapHelpersPath -PathType Leaf)) {
    throw "Bootstrap helper functions not found at $bootstrapHelpersPath"
}

. $bootstrapHelpersPath

# =============================================================================
# Section: App-list helpers
# =============================================================================

function Import-AppListConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    try {
        $config = Import-PowerShellDataFile -Path $Path
    }
    catch {
        throw "Failed to read app list file '$Path'. Ensure it is a valid PowerShell data file."
    }

    if ($config -isnot [hashtable]) {
        throw "Invalid app list file '$Path'. Expected a PowerShell data file with a top-level hashtable."
    }

    if (-not $config.ContainsKey("Apps")) {
        throw "Invalid app list file '$Path'. Expected a top-level 'Apps' entry."
    }

    if ($config.Apps -is [string] -or $config.Apps -isnot [System.Collections.IEnumerable]) {
        throw "Invalid app list file '$Path'. 'Apps' must be an array of app IDs."
    }

    $apps = @($config.Apps)
    foreach ($app in $apps) {
        if ($app -isnot [string]) {
            throw "Invalid app list file '$Path'. Each Apps entry must be a string app ID."
        }
    }

    return $config
}

function New-EmptyAppListFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    @'
@{
    Apps = @(
    )
}
'@ | Set-Content -Path $Path -Encoding ASCII

    Write-WarnLine "Created template app list at $Path"
    Write-InfoLine "Add app IDs to the Apps array and run the script again."
}

function Resolve-AppListPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $DefaultPath
    )

    if (Test-Path $DefaultPath -PathType Leaf) {
        try {
            [void](Import-AppListConfig -Path $DefaultPath)
            return $DefaultPath
        }
        catch {
            Write-WarnLine "Existing app list is invalid: $DefaultPath"
            New-EmptyAppListFile -Path $DefaultPath
            return $DefaultPath
        }
    }

    Write-WarnLine "App list not found at $DefaultPath"

    $inputPath = Read-Host "Enter the path to a .psd1 app list file"
    $inputPath = $inputPath.Trim().Trim('"')

    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        New-EmptyAppListFile -Path $DefaultPath
        return $DefaultPath
    }

    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        New-EmptyAppListFile -Path $DefaultPath
        return $DefaultPath
    }

    if ([System.IO.Path]::GetExtension($inputPath) -ne ".psd1") {
        New-EmptyAppListFile -Path $DefaultPath
        return $DefaultPath
    }

    try {
        [void](Import-AppListConfig -Path $inputPath)
    }
    catch {
        New-EmptyAppListFile -Path $DefaultPath
        return $DefaultPath
    }

    $destinationDirectory = Split-Path -Parent $DefaultPath
    if (-not (Test-Path $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    Copy-Item -LiteralPath $inputPath -Destination $DefaultPath -Force
    Write-SuccessLine "Copied app list to $DefaultPath"
    return $DefaultPath
}

# =============================================================================
# Section: Main
# =============================================================================

Write-Section -Step "0" -Title "Windows Software Installation"
Write-InfoLine "Starting installation workflow."

# =============================================================================
# Section: Configuration
# =============================================================================

$appListPath = Join-Path $PSScriptRoot "private\windows_apps.psd1"

# =============================================================================
# Section: Environment validation
# =============================================================================

if (-not $env:TEMP) {
    throw "The TEMP environment variable is not set."
}

if ($env:OS -ne "Windows_NT") {
    throw "This script must be run on Windows."
}

$wingetCommand = Get-WinGetCommand
if (-not $wingetCommand) {
    Invoke-SystemRequirementsInstaller -Reason "winget is not available. Installing system requirements first."
    $wingetCommand = Get-WinGetCommand
    if (-not $wingetCommand) {
        throw "winget is still not available after running install_system_requirements.ps1."
    }
    Write-SuccessLine "winget is available."
}
else {
    Write-SuccessLine "winget is available."
}

$appListPath = Resolve-AppListPath -DefaultPath $appListPath

# =============================================================================
# Section: Load app list
# =============================================================================

Write-Section -Step "1" -Title "Load Application List"

$appConfig = Import-AppListConfig -Path $appListPath

$apps = @(
    $appConfig.Apps |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } |
        Select-Object -Unique
)

if ($apps.Count -eq 0) {
    throw "No apps were defined in $appListPath."
}

Write-SuccessLine ("Loaded {0} app(s) from {1}" -f $apps.Count, $appListPath)

# =============================================================================
# Section: Install applications
# =============================================================================

Write-Section -Step "2" -Title "Install Applications"

foreach ($app in $apps) {
    Write-InstallStart -Name $app
    & $wingetCommand install -e --id $app --accept-package-agreements --accept-source-agreements
}

# =============================================================================
# Section: Finish
# =============================================================================

Write-Section -Step "3" -Title "Finish"
Write-SuccessLine "All installations complete."
Read-Host "Press Enter to exit"
