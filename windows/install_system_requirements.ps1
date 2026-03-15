param(
    [switch] $NoPause
)

<#
# =============================================================================
# README - Windows system requirements installer
# =============================================================================
#
# Purpose
# -------
# Installs the Windows prerequisites used by the machine setup scripts.
#
# Default behavior
# ----------------
# - Re-launches itself with administrator rights when needed
# - Installs Microsoft App Installer if `winget` is not available
# - Installs the `PSWindowsUpdate` module when it is not already available
# - Imports `PSWindowsUpdate` after installation to confirm availability
#
# Example:
#   .\install_system_requirements.ps1
#
# Notes
# -----
# - This script is intended for Windows PowerShell or PowerShell on Windows
# - Internet access is required to install missing dependencies
# - A new PowerShell session may be needed after installing `winget`
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

function Install-WinGet {
    if (-not $env:TEMP) {
        throw "The TEMP environment variable is not set."
    }

    $downloadUri = "https://aka.ms/getwinget"
    $installerPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"

    Write-WarnLine "winget was not found. Downloading Microsoft App Installer."

    Invoke-WebRequest -Uri $downloadUri -OutFile $installerPath
    Add-AppxPackage -Path $installerPath

    $wingetCommand = Get-WinGetCommand
    if (-not $wingetCommand) {
        throw "winget was installed, but is not available in this session yet. Open a new PowerShell window and run the script again."
    }

    Write-SuccessLine "Microsoft App Installer is available."
    return $wingetCommand
}

function Install-PSWindowsUpdateModule {
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Write-SuccessLine "PSWindowsUpdate module is available."
        return
    }

    Write-InfoLine "Installing PSWindowsUpdate module."
    Install-Module -Name PSWindowsUpdate -Repository PSGallery -Force -Confirm:$false
    Write-SuccessLine "PSWindowsUpdate module installed."
}

# =============================================================================
# Section: Main
# =============================================================================

Write-Section -Step "0" -Title "Windows System Requirements"
Write-InfoLine "Starting system requirements installation."

# =============================================================================
# Section: Environment validation
# =============================================================================

if ($env:OS -ne "Windows_NT") {
    throw "This script must be run on Windows."
}

Write-SuccessLine "Windows environment checks passed."

# =============================================================================
# Section: Administrator elevation
# =============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-WarnLine "Administrator privileges are required to run this script."
    Write-InfoLine "Re-launching with elevated rights."

    $powerShellExecutable = Get-PowerShellExecutable
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($NoPause) {
        $argumentList += " -NoPause"
    }

    $elevatedProcess = Start-Process -FilePath $powerShellExecutable `
        -ArgumentList $argumentList `
        -PassThru `
        -Wait `
        -Verb RunAs

    exit $elevatedProcess.ExitCode
}

Write-SuccessLine "Administrator privileges confirmed."

try {
    # =========================================================================
    # Section: Prepare session
    # =========================================================================

    Write-Section -Step "1" -Title "Prepare Session"

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-SuccessLine "Process execution policy configured."

    # =========================================================================
    # Section: Install winget
    # =========================================================================

    Write-Section -Step "2" -Title "Install winget"

    $wingetCommand = Get-WinGetCommand
    if (-not $wingetCommand) {
        $wingetCommand = Install-WinGet
    }
    else {
        Write-SuccessLine "winget is available."
    }

    # =========================================================================
    # Section: Install PSWindowsUpdate
    # =========================================================================

    Write-Section -Step "3" -Title "Install PSWindowsUpdate"

    Install-PSWindowsUpdateModule
    Import-Module PSWindowsUpdate
    Write-SuccessLine "PSWindowsUpdate module imported."

    # =========================================================================
    # Section: Finish
    # =========================================================================

    Write-Section -Step "4" -Title "Finish"
    Write-SuccessLine "System requirements installation complete."
}
catch {
    Write-FailLine $_.Exception.Message
    Write-Error $_
    exit 1
}

if (-not $NoPause) {
    Read-Host "Press Enter to exit"
}
