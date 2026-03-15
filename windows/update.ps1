<#
# =============================================================================
# README - Windows update workflow
# =============================================================================
#
# Purpose
# -------
# Installs Windows updates and upgrades installed winget packages.
#
# Default behavior
# ----------------
# - Re-launches itself with administrator rights when needed
# - Runs `install_system_requirements.ps1` when `winget` or `PSWindowsUpdate` is missing
# - Installs applicable Windows updates without forcing an immediate reboot
# - Upgrades all available winget packages silently
# - Warns when Windows reports that a reboot is required
#
# Example:
#   .\update.ps1
#
# Notes
# -----
# - This script is intended for Windows PowerShell or PowerShell on Windows
# - Internet access may be required to install missing system requirements
# - A reboot may still be required after updates finish
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
# Section: Main
# =============================================================================

Write-Section -Step "0" -Title "Windows Update Workflow"
Write-InfoLine "Starting update workflow."

# =============================================================================
# Section: Environment validation
# =============================================================================

if ($env:OS -ne "Windows_NT") {
    throw "This script must be run on Windows."
}

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
    $elevatedProcess = Start-Process -FilePath $powerShellExecutable `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -PassThru `
        -Wait `
        -Verb RunAs

    exit $elevatedProcess.ExitCode
}

Write-SuccessLine "Administrator privileges confirmed."

try {
    # =========================================================================
    # Section: Prepare update tools
    # =========================================================================

    Write-Section -Step "1" -Title "Prepare Update Tools"

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-SuccessLine "Process execution policy configured."

    $wingetCommand = Get-WinGetCommand
    $psWindowsUpdateAvailable = [bool](Get-Module -ListAvailable -Name PSWindowsUpdate)

    if ((-not $wingetCommand) -or (-not $psWindowsUpdateAvailable)) {
        Invoke-SystemRequirementsInstaller -Reason "Required update dependencies are missing. Installing system requirements first."
        $wingetCommand = Get-WinGetCommand
        $psWindowsUpdateAvailable = [bool](Get-Module -ListAvailable -Name PSWindowsUpdate)
    }

    if (-not $psWindowsUpdateAvailable) {
        throw "PSWindowsUpdate is still not available after running install_system_requirements.ps1."
    }

    Import-Module PSWindowsUpdate
    Write-SuccessLine "PSWindowsUpdate module imported."

    if (-not $wingetCommand) {
        throw "winget is still not available after running install_system_requirements.ps1."
    }

    Write-SuccessLine "PSWindowsUpdate module is available."
    Write-SuccessLine "winget is available."

    # =========================================================================
    # Section: Windows Update
    # =========================================================================

    Write-Section -Step "2" -Title "Install Windows Updates"

    $wuResults = @(Get-WindowsUpdate -Install -IgnoreReboot)

    if ($wuResults.Count -eq 0) {
        Write-WarnLine "No Windows updates were applicable."
    }
    else {
        Write-SuccessLine ("Installed {0} Windows update(s)." -f $wuResults.Count)
    }

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        Write-WarnLine "Reboot is required to finish installing updates."
    }
    else {
        Write-SuccessLine "No reboot required by Windows Update."
    }

    # =========================================================================
    # Section: winget upgrade
    # =========================================================================

    Write-Section -Step "3" -Title "Upgrade winget Packages"
    Write-InfoLine "Upgrading installed packages with winget."

    & $wingetCommand upgrade --all --silent --accept-source-agreements --accept-package-agreements --include-unknown

    Write-SuccessLine "winget upgrade command completed."

    # =========================================================================
    # Section: Finish
    # =========================================================================

    Write-Section -Step "4" -Title "Finish"
    Write-SuccessLine "Update workflow complete."
}
catch {
    Write-FailLine $_.Exception.Message
    Write-Error $_
    exit 1
}

Read-Host "Press Enter to exit"
