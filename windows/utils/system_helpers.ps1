function Get-PowerShellExecutable {
    $currentProcess = Get-Process -Id $PID -ErrorAction Stop
    if ($currentProcess.Path) {
        return $currentProcess.Path
    }

    if ($PSVersionTable.PSEdition -eq "Core") {
        $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshCommand) {
            return $pwshCommand.Source
        }
    }

    $powershellCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($powershellCommand) {
        return $powershellCommand.Source
    }

    throw "Unable to locate a PowerShell executable for this session."
}

function Get-WinGetCommand {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($appInstaller) {
        $bundledWinget = Join-Path $appInstaller.InstallLocation "winget.exe"
        if (Test-Path $bundledWinget) {
            return $bundledWinget
        }
    }

    return $null
}
