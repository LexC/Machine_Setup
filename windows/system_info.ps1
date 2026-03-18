<#
# =============================================================================
# README - Get relevant PC info
# =============================================================================
#
# Purpose
# -------
# Displays a concise set of relevant Windows PC details.
#
# Default behavior
# ----------------
# - Validates that the script is running on Windows
# - Loads the shared write helpers for consistent section output
# - Reports operating system, motherboard, BIOS, CPU, RAM, GPU, and disk information
# - Continues reporting other sections when a single CIM query fails
#
# Example:
#   .\system_info.ps1
#
# Notes
# -----
# - This script is read-only and does not modify the machine
# - Run it in PowerShell on Windows for the expected CIM/WMI data
#
# =============================================================================
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$isDotSourced = $MyInvocation.InvocationName -eq "."

# =============================================================================
# Section: Load helpers
# =============================================================================

$writeHelpersPath = Join-Path $PSScriptRoot "utils\write_helpers.ps1"
if (-not (Test-Path $writeHelpersPath -PathType Leaf)) {
    throw "Write helper functions not found at $writeHelpersPath"
}

. $writeHelpersPath

# =============================================================================
# Section: Output helpers
# =============================================================================

function Write-DetailLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Label,

        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    Write-Host ("  {0}: {1}" -f $Label, $Value)
}

function Format-BytesAsGigabytes {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [double] $Bytes
    )

    if ($null -eq $Bytes -or $Bytes -le 0) {
        return "Unknown"
    }

    return ("{0:N2} GB" -f ($Bytes / 1GB))
}

function Format-Megahertz {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [double] $Megahertz
    )

    if ($null -eq $Megahertz -or $Megahertz -le 0) {
        return "Unknown"
    }

    return ("{0:N0} MHz" -f $Megahertz)
}

function Format-Percentage {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [double] $Value
    )

    if ($null -eq $Value -or [double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        return "Unknown"
    }

    return ("{0:N1}%" -f $Value)
}

function Get-CimInstancesSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ClassName,

        [Parameter(Mandatory = $true)]
        [string] $FailureMessage,

        [Parameter(Mandatory = $false)]
        [string] $Filter
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Filter)) {
            return @(Get-CimInstance -ClassName $ClassName)
        }

        return @(Get-CimInstance -ClassName $ClassName -Filter $Filter)
    }
    catch {
        Write-WarnLine ("{0} ({1})" -f $FailureMessage, $_.Exception.Message)
        return @()
    }
}

# =============================================================================
# Section: Main
# =============================================================================

Write-Title -Title "Get Relevant PC Info"
Write-InfoLine "Collecting system information."

try {
    # =========================================================================
    # Section: Environment validation
    # =========================================================================

    if ($env:OS -ne "Windows_NT") {
        throw "This script must be run on Windows."
    }

    Write-SuccessLine "Windows environment checks passed."

    # =========================================================================
    # Section: Operating system
    # =========================================================================

    Write-Section -Step "1" -Title "Operating System"

    $osInstances = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_OperatingSystem" `
            -FailureMessage "Unable to query operating system information."
    )

    if ($osInstances.Count -eq 0) {
        Write-WarnLine "Operating system details are unavailable."
    }
    else {
        $os = $osInstances[0]
        Write-DetailLine -Label "Name" -Value $os.Caption
        Write-DetailLine -Label "Version" -Value $os.Version
    }

    # =========================================================================
    # Section: Motherboard and BIOS
    # =========================================================================

    Write-Section -Step "2" -Title "Motherboard and BIOS"

    $computerSystems = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_ComputerSystem" `
            -FailureMessage "Unable to query motherboard information."
    )

    if ($computerSystems.Count -eq 0) {
        Write-WarnLine "Motherboard details are unavailable."
    }
    else {
        $computerSystem = $computerSystems[0]
        $manufacturer = if ([string]::IsNullOrWhiteSpace($computerSystem.Manufacturer)) {
            "Unknown"
        }
        else {
            $computerSystem.Manufacturer.Trim()
        }

        $model = if ([string]::IsNullOrWhiteSpace($computerSystem.Model)) {
            "Unknown"
        }
        else {
            $computerSystem.Model.Trim()
        }

        Write-DetailLine -Label "Manufacturer" -Value $manufacturer
        Write-DetailLine -Label "Model" -Value $model
    }

    $biosInstances = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_BIOS" `
            -FailureMessage "Unable to query BIOS information."
    )

    if ($biosInstances.Count -eq 0) {
        Write-WarnLine "BIOS details are unavailable."
    }
    else {
        $bios = $biosInstances[0]
        $biosVersion = @(
            $bios.BIOSVersion |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }
        ) -join "; "

        if ([string]::IsNullOrWhiteSpace($biosVersion)) {
            $biosVersion = if ([string]::IsNullOrWhiteSpace($bios.SMBIOSBIOSVersion)) {
                "Unknown"
            }
            else {
                $bios.SMBIOSBIOSVersion.Trim()
            }
        }

        Write-DetailLine -Label "BIOS Version" -Value $biosVersion
    }

    # =========================================================================
    # Section: Processor and memory
    # =========================================================================

    Write-Section -Step "3" -Title "Processor and Memory"

    $processors = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_Processor" `
            -FailureMessage "Unable to query processor information."
    )

    if ($processors.Count -eq 0) {
        Write-WarnLine "No processor information was returned."
        $cpuSummary = "Unknown"
    }
    else {
        # Sum across all CPU packages so multi-socket systems are reported
        # accurately instead of relying on a single processor instance.
        $cpuNames = @(
            $processors |
                ForEach-Object {
                    if ([string]::IsNullOrWhiteSpace($_.Name)) {
                        "Unknown"
                    }
                    else {
                        $_.Name.Trim()
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )

        $cpuSummary = if ($cpuNames.Count -gt 0) {
            $cpuNames -join "; "
        }
        else {
            "Unknown"
        }

        $totalCores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        $totalThreads = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $maxClockSpeed = ($processors | Measure-Object -Property MaxClockSpeed -Maximum).Maximum

        Write-DetailLine -Label "Model" -Value $cpuSummary
        Write-DetailLine -Label "CPU Packages" -Value ([string] $processors.Count)
        Write-DetailLine -Label "Cores" -Value ([string] $totalCores)
        Write-DetailLine -Label "Threads" -Value ([string] $totalThreads)
        Write-DetailLine -Label "Max Clock" -Value (Format-Megahertz -Megahertz $maxClockSpeed)
    }

    $memoryModules = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_PhysicalMemory" `
            -FailureMessage "Unable to query physical memory information."
    )

    $totalRamBytes = ($memoryModules | Measure-Object -Property Capacity -Sum).Sum
    $totalRamDisplay = Format-BytesAsGigabytes -Bytes $totalRamBytes

    if ($memoryModules.Count -eq 0 -or $totalRamDisplay -eq "Unknown") {
        Write-WarnLine "Unable to determine installed physical memory."
    }
    else {
        Write-DetailLine -Label "Installed RAM" -Value $totalRamDisplay
    }

    # =========================================================================
    # Section: Graphics
    # =========================================================================

    Write-Section -Step "4" -Title "Graphics"

    $gpus = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_VideoController" `
            -FailureMessage "Unable to query graphics information."
    )

    if ($gpus.Count -eq 0) {
        Write-WarnLine "No GPU information was returned."
        $gpuNames = @("Unknown")
    }
    else {
        $gpuNames = @()

        foreach ($gpu in $gpus) {
            $gpuName = if ([string]::IsNullOrWhiteSpace($gpu.Name)) {
                "Unknown"
            }
            else {
                $gpu.Name.Trim()
            }

            $gpuNames += $gpuName

            Write-DetailLine -Label "Name" -Value $gpuName
            Write-DetailLine -Label "VRAM" -Value (Format-BytesAsGigabytes -Bytes $gpu.AdapterRAM)
        }
    }

    # =========================================================================
    # Section: Storage
    # =========================================================================

    Write-Section -Step "5" -Title "Storage"

    $disks = @(
        Get-CimInstancesSafe `
            -ClassName "Win32_LogicalDisk" `
            -FailureMessage "Unable to query storage information." `
            -Filter "DriveType=3"
    )

    if ($disks.Count -eq 0) {
        Write-WarnLine "No fixed disks were returned."
    }
    else {
        foreach ($disk in $disks) {
            $freeSpace = Format-BytesAsGigabytes -Bytes $disk.FreeSpace
            $totalSpace = Format-BytesAsGigabytes -Bytes $disk.Size

            if ($null -eq $disk.Size -or $disk.Size -le 0) {
                $freePercentage = "Unknown"
            }
            else {
                $freePercentage = Format-Percentage -Value (($disk.FreeSpace / $disk.Size) * 100)
            }

            Write-DetailLine -Label ("Drive {0}" -f $disk.DeviceID) -Value ("{0} free ({1}) / {2} total" -f $freeSpace, $freePercentage, $totalSpace)
        }
    }

    # =========================================================================
    # Section: Finish
    # =========================================================================

    Write-Section -Step "6" -Title "Finish"
    Write-SuccessLine "PC information check complete."
}
catch {
    Write-FailLine $_.Exception.Message
    Write-Error $_

    if ($isDotSourced) {
        return
    }

    exit 1
}

Read-Host "Press Enter to exit"
