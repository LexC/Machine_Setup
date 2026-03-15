$WindowsScriptsRoot = Split-Path -Parent $PSScriptRoot

function Invoke-SystemRequirementsInstaller {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Reason
    )

    $requirementsScript = Join-Path $WindowsScriptsRoot "install_system_requirements.ps1"
    if (-not (Test-Path $requirementsScript -PathType Leaf)) {
        throw "System requirements installer not found at $requirementsScript"
    }

    $powershellCommand = Get-PowerShellExecutable

    Write-WarnLine $Reason
    Write-InfoLine "Running install_system_requirements.ps1."

    & $powershellCommand -NoProfile -ExecutionPolicy Bypass -File $requirementsScript -NoPause

    if ($LASTEXITCODE -ne 0) {
        throw "install_system_requirements.ps1 failed with exit code $LASTEXITCODE."
    }
}
