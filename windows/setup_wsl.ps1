[CmdletBinding()]
param(
    [string] $Action,
    [switch] $Help
)

<#
# =============================================================================
# README - WSL Ubuntu setup
# =============================================================================
#
# Purpose
# -------
# Installs or removes WSL and an Ubuntu distribution from Windows.
#
# Default behavior
# ----------------
# - Re-launches itself with administrator rights when needed
# - Installs the WSL platform when it is not fully available
# - Installs Ubuntu when WSL exists but no Ubuntu distribution is present
# - Leaves existing WSL and Ubuntu installations untouched when they are
#   already ready
#
# Actions
# -------
# - Default: install or repair WSL and Ubuntu
# - `-Action UninstallDistros`: unregister all installed WSL distributions
# - `-Action UninstallWsl`: unregister all distributions, disable WSL platform
#   features, and remove the WSL app package
#
# Example:
#   .\windows\setup_wsl.ps1
#
# Notes
# -----
# - This script is intended for Windows PowerShell or PowerShell on Windows
# - Internet access may be required for WSL or Ubuntu installation
# - A Windows restart may be required before WSL or Ubuntu is fully usable
# - This workflow currently assumes English `wsl.exe` output when interpreting
#   some command results and status messages
# - Non-English Windows or WSL output may require script updates before this
#   workflow behaves correctly
#
# =============================================================================
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:RebootRequired = $false

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

# =============================================================================
# Section: WSL helpers
# =============================================================================

function Throw-WslFailure {
    param(
        [string] $Command,
        [pscustomobject] $Result
    )

    $message = @("Command failed: $Command", "Exit code: $($Result.Code)")
    if ($Result.Text) {
        $message += "Output:"
        $message += $Result.Text
    }

    throw ($message -join [Environment]::NewLine)
}

function Invoke-Wsl {
    param(
        [string[]] $Arguments
    )

    $output = @(& wsl.exe @Arguments 2>&1)
    $text = (($output | ForEach-Object {
        (($_.ToString()).Replace([string] [char] 0, "") -replace "[\x01-\x08\x0B\x0C\x0E-\x1F]", "").Trim()
    }) -join [Environment]::NewLine).Trim()

    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
}

function Get-InstalledDistributions {
    $result = Invoke-Wsl -Arguments @("--list", "--quiet")
    if ($result.Code -ne 0) {
        if ($result.Text -match "(?i)has no installed distributions") {
            return @()
        }

        Throw-WslFailure -Command "wsl --list --quiet" -Result $result
    }

    return @($result.Text -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-InstalledDistributionsOrEmpty {
    try {
        return @(Get-InstalledDistributions)
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match "(?i)required feature is not installed|optional component is not enabled|has not been enabled|WSL_E_WSL_NOT_INSTALLED") {
            return @()
        }

        throw
    }
}

function Remove-Distributions {
    param(
        [string[]] $DistributionNames
    )

    if (-not $DistributionNames) {
        return @()
    }

    $shutdown = Invoke-Wsl -Arguments @("--shutdown")
    if ($shutdown.Code -eq 0) {
        Write-SuccessLine "WSL runtime stopped."
    }
    elseif ($shutdown.Text -match "(?i)has no installed distributions|there is no distribution") {
        Write-InfoLine "No installed WSL distributions were running."
    }
    elseif ($shutdown.Text -match "(?i)\b(restart|reboot)\b") {
        $script:RebootRequired = $true
        throw "Restart Windows before continuing. WSL reports a pending restart."
    }
    else {
        Throw-WslFailure -Command "wsl --shutdown" -Result $shutdown
    }

    $removed = @()
    foreach ($distributionName in $DistributionNames) {
        Write-InfoLine "Unregistering distribution '$distributionName'."
        $result = Invoke-Wsl -Arguments @("--unregister", $distributionName)
        if ($result.Code -ne 0) {
            Throw-WslFailure -Command "wsl --unregister $distributionName" -Result $result
        }

        $removed += $distributionName
        Write-SuccessLine "Distribution '$distributionName' was unregistered."
    }

    return $removed
}

if ($Help) {
    Write-Title "WSL Ubuntu Setup"
    Write-Host "Usage: .\windows\setup_wsl.ps1 [-Action UninstallDistros|UninstallWsl] [-Help]"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Action)) {
    $Action = $null
}

$actionMode = if ([string]::IsNullOrWhiteSpace($Action)) {
    "Install"
}
else {
    $Action
}

$validActions = @("UninstallDistros", "UninstallWsl")
if ($Action -and ($Action -notin $validActions)) {
    throw "Unsupported action '$Action'. Valid values: $($validActions -join ', ')."
}

# =============================================================================
# Section: Main
# =============================================================================

Write-Section -Step "0" -Title "WSL Ubuntu Setup"
Write-InfoLine "Starting WSL workflow."

# =============================================================================
# Section: Environment validation
# =============================================================================

if ($env:OS -ne "Windows_NT") {
    throw "This script must be run on Windows."
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe was not found. This Windows installation does not expose the WSL command."
}

Write-SuccessLine "Windows environment checks passed."

# =============================================================================
# Section: Administrator elevation
# =============================================================================

$isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    Write-WarnLine "Administrator privileges are required to run this script."
    Write-InfoLine "Re-launching with elevated rights."

    $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"{0}"' -f $PSCommandPath))
    if ($Action) { $argumentList += @("-Action", $Action) }

    $process = Start-Process -FilePath (Get-PowerShellExecutable) `
        -ArgumentList $argumentList `
        -Verb RunAs `
        -PassThru `
        -Wait

    exit $process.ExitCode
}

Write-SuccessLine "Administrator privileges confirmed."

# =============================================================================
# Section: Summary state
# =============================================================================

$installSummary = [pscustomobject]@{
    WslReady = $false
    UbuntuDistribution = $null
    UbuntuInstalledThisRun = $false
}

$uninstallSummary = [pscustomobject]@{
    RemovedDistributions = @()
    DisabledFeatures = @()
    RemovedPackages = @()
    HasChanges = $false
    RestartRequiredBeforeRemoval = $false
}

try {
    # =========================================================================
    # Section: Prepare session
    # =========================================================================

    Write-Section -Step "1" -Title "Prepare Session"

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-SuccessLine "Process execution policy configured."

    switch ($actionMode) {
        "Install" {
            # =================================================================
            # Section: Install WSL
            # =================================================================

            Write-Section -Step "2" -Title "Install WSL"

            $status = Invoke-Wsl -Arguments @("--status")
            $wslReady = ($status.Code -eq 0)

            if (-not $wslReady) {
                Write-InfoLine "WSL is not ready. Installing required WSL components."
                $wslInstall = Invoke-Wsl -Arguments @("--install", "--no-distribution")

                if (($wslInstall.Code -ne 0) -and ($wslInstall.Text -match "(?i)no-distribution|invalid command line option|invalid option")) {
                    throw "This WSL version does not support 'wsl --install --no-distribution'. Update WSL before using this script."
                }

                if (($wslInstall.Code -ne 0) -and (-not ($wslInstall.Text -match "(?i)\b(restart|reboot)\b"))) {
                    Throw-WslFailure -Command "wsl --install --no-distribution" -Result $wslInstall
                }

                $status = Invoke-Wsl -Arguments @("--status")
                $wslReady = ($status.Code -eq 0)

                if (-not $wslReady) {
                    if (($wslInstall.Text + [Environment]::NewLine + $status.Text) -match "(?i)\b(restart|reboot)\b") {
                        $script:RebootRequired = $true
                        Write-WarnLine "Windows reports that a restart is required before WSL becomes available."
                    }
                    else {
                        Throw-WslFailure -Command "wsl --status" -Result $status
                    }
                }
            }

            if ($wslReady) {
                Write-SuccessLine "WSL is available."
            }

            # =================================================================
            # Section: Install Ubuntu
            # =================================================================

            Write-Section -Step "3" -Title "Install Ubuntu"

            $ubuntuDistribution = $null
            $ubuntuInstalledThisRun = $false

            if ($wslReady) {
                $distributions = @(Get-InstalledDistributions)
                $ubuntuDistribution = $distributions | Where-Object { $_ -match "^Ubuntu(?:$|-)" } | Select-Object -First 1

                if ($ubuntuDistribution) {
                    Write-SuccessLine "Ubuntu distribution '$ubuntuDistribution' is already installed."
                }
                else {
                    Write-InfoLine "Ubuntu distribution not found. Installing Ubuntu without launching it."
                    $ubuntuInstall = Invoke-Wsl -Arguments @("--install", "-d", "Ubuntu", "--no-launch")

                    if (($ubuntuInstall.Code -ne 0) -and ($ubuntuInstall.Text -match "(?i)no-launch|invalid command line option|invalid option")) {
                        throw "This WSL version does not support 'wsl --install -d Ubuntu --no-launch'. Update WSL before using this script."
                    }

                    if ($ubuntuInstall.Code -ne 0) {
                        if ($ubuntuInstall.Text -match "(?i)ERROR_ALREADY_EXISTS|already exists") {
                            $ubuntuDistribution = (Get-InstalledDistributionsOrEmpty | Where-Object { $_ -match "^Ubuntu(?:$|-)" } | Select-Object -First 1)
                            if ($ubuntuDistribution) {
                                Write-WarnLine "Ubuntu distribution '$ubuntuDistribution' already exists."
                            }
                            else {
                                Write-WarnLine "Windows reported that the Ubuntu distribution already exists."
                            }
                        }
                        elseif ($ubuntuInstall.Text -match "(?i)\b(restart|reboot)\b") {
                            $script:RebootRequired = $true
                            Write-WarnLine "Ubuntu installation started, but a restart is required before registration can finish."
                        }
                        else {
                            Throw-WslFailure -Command "wsl --install -d Ubuntu --no-launch" -Result $ubuntuInstall
                        }
                    }
                    else {
                        $ubuntuInstalledThisRun = $true
                        $ubuntuDistribution = (Get-InstalledDistributionsOrEmpty | Where-Object { $_ -match "^Ubuntu(?:$|-)" } | Select-Object -First 1)
                        if ($ubuntuDistribution) {
                            Write-SuccessLine "Ubuntu distribution '$ubuntuDistribution' is installed."
                        }
                        else {
                            $script:RebootRequired = $true
                            Write-WarnLine "Ubuntu was installed, but it is not visible yet."
                        }
                    }
                }
            }

            $installSummary = [pscustomobject]@{
                WslReady = $wslReady
                UbuntuDistribution = $ubuntuDistribution
                UbuntuInstalledThisRun = $ubuntuInstalledThisRun
            }
        }

        "UninstallDistros" {
            # =================================================================
            # Section: Remove WSL distributions
            # =================================================================

            Write-Section -Step "2" -Title "Remove WSL Distributions"
            $distributions = @(Get-InstalledDistributionsOrEmpty)

            if ($distributions.Count -eq 0) {
                Write-WarnLine "No installed WSL distributions were found."
            }
            else {
                Write-InfoLine "Installed WSL distributions: $($distributions -join ', ')."
                $uninstallSummary.RemovedDistributions = @(Remove-Distributions -DistributionNames $distributions)
            }
        }

        "UninstallWsl" {
            # =================================================================
            # Section: Remove WSL distributions
            # =================================================================

            $featureNames = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")
            $enabledFeatures = @($featureNames | Where-Object {
                (Get-WindowsOptionalFeature -Online -FeatureName $_).State -notmatch "^Disabled"
            })
            $packages = @(Get-AppxPackage -Name "*WindowsSubsystemForLinux*" -ErrorAction SilentlyContinue)

            Write-Section -Step "2" -Title "Remove WSL Distributions"

            $status = Invoke-Wsl -Arguments @("--status")
            if ($status.Text -match "(?i)\b(restart|reboot)\b") {
                $script:RebootRequired = $true
                Write-WarnLine "WSL currently reports a pending restart."
                $uninstallSummary.RestartRequiredBeforeRemoval = $true
                break
            }

            $distributions = @(Get-InstalledDistributionsOrEmpty)

            if (($distributions.Count -eq 0) -and ($enabledFeatures.Count -eq 0) -and ($packages.Count -eq 0)) {
                Write-WarnLine "No WSL installation was found to remove."
                break
            }

            if ($distributions.Count -gt 0) {
                Write-InfoLine "Installed WSL distributions: $($distributions -join ', ')."
                $uninstallSummary.RemovedDistributions = @(Remove-Distributions -DistributionNames $distributions)
            }
            else {
                Write-InfoLine "No installed WSL distributions were found."
            }

            # =================================================================
            # Section: Remove WSL platform
            # =================================================================

            Write-Section -Step "3" -Title "Remove WSL Platform"

            foreach ($featureName in $enabledFeatures) {
                Write-InfoLine "Disabling feature '$featureName'."
                $result = Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart
                if ($result.RestartNeeded) {
                    $script:RebootRequired = $true
                }

                $uninstallSummary.DisabledFeatures += $featureName
                Write-SuccessLine "Feature '$featureName' disabled."
            }

            if ($packages.Count -eq 0) {
                Write-InfoLine "No Windows Subsystem for Linux app package was found for the current user."
            }
            else {
                foreach ($package in $packages) {
                    Write-InfoLine "Removing app package '$($package.Name)'."
                    Remove-AppxPackage -Package $package.PackageFullName
                    $uninstallSummary.RemovedPackages += $package.Name
                    Write-SuccessLine "App package '$($package.Name)' removed."
                }
            }

            $uninstallSummary.HasChanges = ($uninstallSummary.RemovedDistributions.Count -gt 0) -or
                ($uninstallSummary.DisabledFeatures.Count -gt 0) -or
                ($uninstallSummary.RemovedPackages.Count -gt 0)

            if ($uninstallSummary.HasChanges) { $script:RebootRequired = $true }
        }
        default { throw "Unsupported action '$Action'." }
    }

    # =========================================================================
    # Section: Finish
    # =========================================================================

    Write-Section -Step "4" -Title "Finish"

    switch ($actionMode) {
        "Install" {
            if ($installSummary.WslReady -and $installSummary.UbuntuDistribution) {
                Write-SuccessLine "WSL is ready and Ubuntu is installed."
            }
            elseif ($installSummary.WslReady) {
                Write-WarnLine "WSL is available, but Ubuntu still needs attention."
            }
            else {
                Write-WarnLine "WSL changes were applied, but the platform is not ready yet."
            }

            if ($script:RebootRequired) {
                Write-WarnLine "Restart Windows, then launch Ubuntu manually once to finish first-run initialization."
            }
            elseif ($installSummary.UbuntuInstalledThisRun) {
                Write-InfoLine "Launch Ubuntu manually once to finish first-run initialization and create your Unix user account."
            }
        }

        "UninstallDistros" {
            if ($uninstallSummary.RemovedDistributions.Count -gt 0) {
                Write-SuccessLine "All WSL distributions were unregistered."
            }
            else {
                Write-WarnLine "No WSL distributions were removed."
            }
        }

        "UninstallWsl" {
            if ($uninstallSummary.RestartRequiredBeforeRemoval) {
                Write-WarnLine "A Windows restart is required before WSL removal can continue."
            }
            elseif ($uninstallSummary.HasChanges) {
                Write-SuccessLine "WSL removal commands completed."
            }
            else {
                Write-WarnLine "No WSL components were removed."
            }

            if ($script:RebootRequired) {
                if ($uninstallSummary.RestartRequiredBeforeRemoval) {
                    Write-WarnLine "Restart Windows, then re-run this script to finish removing WSL."
                }
                else {
                    Write-WarnLine "Restart Windows to finish removing WSL."
                }
            }
        }
    }
}
catch {
    Write-FailLine $_.Exception.Message
    Write-Error $_
    exit 1
}
