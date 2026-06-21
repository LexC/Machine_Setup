<#
# =============================================================================
# README - Interactive SSH key setup
# =============================================================================
#
# Purpose
# -------
# Configures passwordless SSH access from Windows to a remote machine or VM
# using a friendly SSH alias.
#
# Default behavior
# ----------------
# - Re-launches itself with administrator rights when needed
# - Prompts for an SSH alias, username, and host/IP address
# - Creates the Windows ~/.ssh directory if it does not exist
# - Creates or updates a managed SSH config alias
# - Creates an Ed25519 SSH key without a passphrase using an automatic key name
# - Starts and enables the Windows ssh-agent service
# - Adds the SSH private key to ssh-agent
# - Copies the public key into the remote ~/.ssh/authorized_keys file
#
# Password behavior
# -----------------
# The first setup may ask for the remote account password while the public key
# is copied. After setup succeeds, future SSH connections should not ask for
# that remote account password.
#
# Security note
# -------------
# This script creates the SSH key without a passphrase for convenience. Anyone
# with access to this Windows user account and private key file may be able to
# SSH into the remote machine.
#
# Example:
#   .\setup_ssh_key.ps1
#   .\setup_ssh_key.ps1 --help
#
# =============================================================================
#>

[CmdletBinding()]
param(
    [switch]$ConfigureSshAgentOnly
)

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

# =============================================================================
# Section: Display helpers
# =============================================================================

function Show-Help {
    Write-Host @"
Interactive SSH key setup for Windows

Usage:
    .\setup_ssh_key.ps1
    .\setup_ssh_key.ps1 --help

Prompts:
    SSH alias          Short name used by ssh
    Remote username    User account on the remote machine
    Remote host/IP     DNS name or IP address of the remote machine

Example prompt answers:
    SSH alias: ubuntu-vm
    Remote username: ubuntu
    Remote host or IP: 192.168.56.101

    You can also use a DNS name for the host, for example:
    Remote host or IP: ubuntu-vm.local

What happens:
    - Creates ~/.ssh if needed.
    - Creates or updates a managed Host block in ~/.ssh/config.
    - Creates an Ed25519 key without a passphrase using an automatic key name.
    - Starts Windows ssh-agent and adds the key.
    - Installs the public key into the remote authorized_keys file.

The remote account password may be required once while the key is installed.
After setup succeeds, test with:

    ssh <alias>
"@
}

# =============================================================================
# Section: Input helpers
# =============================================================================

function Read-Value {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [switch]$Required
    )

    $value = Read-Host $Prompt

    if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
        throw "No value provided for '$Prompt'. Stopping."
    }

    return $value.Trim()
}

# =============================================================================
# Section: Naming helpers
# =============================================================================

function Get-SafeName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $safeName = $Value -replace "[^A-Za-z0-9_.-]", "_"
    $safeName = $safeName.Trim("._-")

    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return "host"
    }

    return $safeName
}

function Get-ShortHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [int]$Length = 12
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hashBytes = $sha256.ComputeHash($bytes)
        $hashText = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })

        return $hashText.Substring(0, [Math]::Min($Length, $hashText.Length))
    }
    finally {
        $sha256.Dispose()
    }
}

function Test-SshAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return $Value -match "^[A-Za-z0-9_.][A-Za-z0-9_.-]*$"
}

# =============================================================================
# Section: Command helpers
# =============================================================================

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @()
    )

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Command '$FilePath' failed with exit code $exitCode."
    }
}

function Invoke-NativeCommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @()
    )

    $output = & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Command '$FilePath' failed with exit code $exitCode."
    }

    return $output
}

function Convert-ToWindowsCommandLineArgument {
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    $backslashCount = 0

    [void]$builder.Append('"')

    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }

        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }

    [void]$builder.Append('"')

    return $builder.ToString()
}

function Invoke-NativeCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @()
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($ArgumentList | ForEach-Object { Convert-ToWindowsCommandLineArgument -Value $_ }) -join " "
    $startInfo.UseShellExecute = $false

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    if ($exitCode -ne 0) {
        throw "Command '$FilePath' failed with exit code $exitCode."
    }
}

function Test-Administrator {
    $principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-SshAgentServiceState {
    $service = Get-Service -Name "ssh-agent" -ErrorAction Stop

    if ($service.StartType -ne "Automatic") {
        Set-Service -Name "ssh-agent" -StartupType Automatic
    }

    if ($service.Status -ne "Running") {
        Start-Service -Name "ssh-agent"
    }
}

function Test-SshAgentNeedsAdministratorConfiguration {
    $service = Get-Service -Name "ssh-agent" -ErrorAction Stop
    return (($service.StartType -ne "Automatic") -or ($service.Status -ne "Running"))
}

function Invoke-ElevatedSshAgentConfiguration {
    if (-not (Test-SshAgentNeedsAdministratorConfiguration)) {
        Write-SuccessLine "ssh-agent is already configured."
        return
    }

    if (Test-Administrator) {
        Set-SshAgentServiceState
        Write-SuccessLine "ssh-agent service is configured."
        return
    }

    Write-WarnLine "Administrator privileges are required to configure ssh-agent."
    Write-InfoLine "Re-launching only the ssh-agent configuration step with elevated rights."

    $powerShellExecutable = Get-PowerShellExecutable
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        ('"{0}"' -f $PSCommandPath),
        "-ConfigureSshAgentOnly"
    )

    $elevatedProcess = Start-Process -FilePath $powerShellExecutable `
        -ArgumentList $argumentList `
        -PassThru `
        -Wait `
        -Verb RunAs

    if ($elevatedProcess.ExitCode -ne 0) {
        throw "Elevated ssh-agent configuration failed with exit code $($elevatedProcess.ExitCode)."
    }
}

function Convert-ToShellSingleQuoted {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $escaped = $Value.Replace("'", "'\''")
    return "'" + $escaped + "'"
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

# =============================================================================
# Section: SSH config helpers
# =============================================================================

function Get-ManagedSshHostIdentityFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$HostAlias
    )

    if (!(Test-Path $ConfigPath)) {
        return $null
    }

    $beginMarker = "# BEGIN setup-ssh-key managed host $HostAlias"
    $endMarker = "# END setup-ssh-key managed host $HostAlias"
    $config = Get-Content $ConfigPath -Raw
    $managedPattern = "(?ms)^" + [regex]::Escape($beginMarker) + "\r?\n(?<Block>.*?)^" + [regex]::Escape($endMarker) + "\r?\n?"
    $match = [regex]::Match($config, $managedPattern)

    if (!$match.Success) {
        return $null
    }

    $blockLines = $match.Groups["Block"].Value -split "\r?\n"

    foreach ($line in $blockLines) {
        if ($line -match "^\s*IdentityFile\s+(.+?)\s*$") {
            return $Matches[1].Trim()
        }
    }

    return $null
}

function Resolve-IdentityFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IdentityFile,

        [Parameter(Mandatory = $true)]
        [string]$SshDir
    )

    $identityPath = [Environment]::ExpandEnvironmentVariables($IdentityFile.Trim())

    if ($identityPath.Length -ge 2) {
        $firstCharacter = $identityPath[0]
        $lastCharacter = $identityPath[$identityPath.Length - 1]

        if (($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or ($firstCharacter -eq "'" -and $lastCharacter -eq "'")) {
            $identityPath = $identityPath.Substring(1, $identityPath.Length - 2)
        }
    }

    if ($identityPath -match "^~[/\\]\.ssh[/\\](.+)$") {
        return Join-Path $SshDir $Matches[1]
    }

    if ($identityPath -match "^~[/\\](.+)$") {
        return Join-Path $env:USERPROFILE $Matches[1]
    }

    if ([System.IO.Path]::IsPathRooted($identityPath)) {
        return $identityPath
    }

    return Join-Path $SshDir $identityPath
}

function Set-ManagedSshHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$HostAlias,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$IdentityFile
    )

    $beginMarker = "# BEGIN setup-ssh-key managed host $HostAlias"
    $endMarker = "# END setup-ssh-key managed host $HostAlias"
    $newBlock = @(
        $beginMarker
        "Host $HostAlias"
        "    HostName $HostName"
        "    User $UserName"
        "    IdentityFile $IdentityFile"
        "    IdentitiesOnly yes"
        "    AddKeysToAgent yes"
        $endMarker
    ) -join [Environment]::NewLine
    $newBlock = $newBlock + [Environment]::NewLine

    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath -Raw
    }
    else {
        $config = ""
    }

    $managedPattern = "(?ms)^" + [regex]::Escape($beginMarker) + "\r?\n.*?^" + [regex]::Escape($endMarker) + "\r?\n?"

    if ($config -match $managedPattern) {
        $config = [regex]::Replace($config, $managedPattern, "")
    }

    $hostLinePattern = "^\s*Host\s+(.+)$"
    $lines = $config -split "\r?\n"

    foreach ($line in $lines) {
        if ($line -match $hostLinePattern) {
            $hostPatterns = $Matches[1] -split "\s+"

            foreach ($hostPattern in $hostPatterns) {
                if ([string]::Equals($hostPattern, $HostAlias, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "An unmanaged SSH config entry for alias '$HostAlias' already exists in $ConfigPath. Rename the alias or edit the existing Host block manually."
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($config)) {
        $updatedConfig = $newBlock
    }
    else {
        $configLines = $config.TrimEnd("`r", "`n") -split "\r?\n"
        $wildcardHostLineIndex = $null

        for ($index = 0; $index -lt $configLines.Count; $index++) {
            if ($configLines[$index] -match $hostLinePattern) {
                $hostPatterns = $Matches[1] -split "\s+"

                foreach ($hostPattern in $hostPatterns) {
                    $normalizedPattern = $hostPattern.TrimStart("!")

                    if ($normalizedPattern.Contains("*") -or $normalizedPattern.Contains("?")) {
                        $wildcardHostLineIndex = $index
                        break
                    }
                }
            }

            if ($null -ne $wildcardHostLineIndex) {
                break
            }
        }

        if ($null -eq $wildcardHostLineIndex) {
            $updatedConfig = $config.TrimEnd("`r", "`n") + [Environment]::NewLine + [Environment]::NewLine + $newBlock
        }
        else {
            $updatedLines = New-Object System.Collections.Generic.List[string]

            for ($index = 0; $index -lt $wildcardHostLineIndex; $index++) {
                $updatedLines.Add($configLines[$index])
            }

            if ($updatedLines.Count -gt 0 -and ![string]::IsNullOrWhiteSpace($updatedLines[$updatedLines.Count - 1])) {
                $updatedLines.Add("")
            }

            foreach ($newBlockLine in ($newBlock.TrimEnd("`r", "`n") -split "\r?\n")) {
                $updatedLines.Add($newBlockLine)
            }

            $updatedLines.Add("")

            for ($index = $wildcardHostLineIndex; $index -lt $configLines.Count; $index++) {
                $updatedLines.Add($configLines[$index])
            }

            $updatedConfig = ($updatedLines -join [Environment]::NewLine).TrimEnd("`r", "`n") + [Environment]::NewLine
        }
    }

    Write-Utf8NoBom -Path $ConfigPath -Value $updatedConfig
}

# =============================================================================
# Section: Main
# =============================================================================

if ($args.Count -gt 0) {
    if ($args.Count -eq 1 -and $args[0] -eq "--help") {
        Show-Help
        exit 0
    }

    throw "Unsupported argument '$($args -join ' ')'. Run .\setup_ssh_key.ps1 --help for usage."
}

# =============================================================================
# Section: Environment validation
# =============================================================================

if ($env:OS -ne "Windows_NT") {
    throw "This script must be run on Windows."
}

if ($ConfigureSshAgentOnly) {
    if (-not (Test-Administrator)) {
        throw "The ssh-agent configuration helper must be run as Administrator."
    }

    Write-Section -Step "0" -Title "Configure ssh-agent"
    Set-SshAgentServiceState
    Write-SuccessLine "ssh-agent service is configured."
    exit 0
}

Write-Section -Step "0" -Title "SSH Key Setup"
Write-InfoLine "Starting SSH key setup workflow."

try {
    # =========================================================================
    # Section: Validate commands
    # =========================================================================

    Write-Section -Step "1" -Title "Validate Commands"

    Require-Command -Name "ssh"
    Require-Command -Name "ssh-add"
    Require-Command -Name "ssh-keygen"
    Write-SuccessLine "Required SSH commands are available."

    # =========================================================================
    # Section: Configuration
    # =========================================================================

    $SshDir = Join-Path $env:USERPROFILE ".ssh"
    $ConfigPath = Join-Path $SshDir "config"

    # =========================================================================
    # Section: Collect connection details
    # =========================================================================

    Write-Section -Step "2" -Title "Collect Connection Details"

    while ($true) {
        $HostAlias = Read-Value -Prompt "SSH alias" -Required

        if (Test-SshAlias -Value $HostAlias) {
            break
        }

        Write-WarnLine "Use only letters, numbers, dots, dashes, and underscores. The alias cannot start with a dash."
    }

    while ($true) {
        $RemoteUser = Read-Value -Prompt "Remote username" -Required

        if ($RemoteUser -notmatch "\s") {
            break
        }

        Write-WarnLine "The remote username cannot contain whitespace."
    }

    while ($true) {
        $RemoteHost = Read-Value -Prompt "Remote host or IP" -Required

        if ($RemoteHost -notmatch "\s") {
            break
        }

        Write-WarnLine "The remote host cannot contain whitespace."
    }

    # =========================================================================
    # Section: Prepare SSH key
    # =========================================================================

    Write-Section -Step "3" -Title "Prepare SSH Key"

    if (!(Test-Path $SshDir)) {
        New-Item -ItemType Directory -Path $SshDir | Out-Null
        Write-SuccessLine "Created SSH directory: $SshDir"
    }
    else {
        Write-SuccessLine "SSH directory is available: $SshDir"
    }

    $ExistingIdentityFile = Get-ManagedSshHostIdentityFile -ConfigPath $ConfigPath -HostAlias $HostAlias
    $IdentityFile = $null
    $KeyPath = $null

    if (![string]::IsNullOrWhiteSpace($ExistingIdentityFile)) {
        $ExistingKeyPath = Resolve-IdentityFilePath -IdentityFile $ExistingIdentityFile -SshDir $SshDir

        if (Test-Path $ExistingKeyPath) {
            $IdentityFile = $ExistingIdentityFile
            $KeyPath = $ExistingKeyPath
            Write-InfoLine "Reusing existing SSH key: $KeyPath"
        }
        else {
            Write-WarnLine "Managed SSH key is missing: $ExistingKeyPath"
            Write-InfoLine "Creating a replacement key for alias '$HostAlias'."
        }
    }

    if ([string]::IsNullOrWhiteSpace($KeyPath)) {
        $KeyTimestamp = (Get-Date).ToString("yyyyMMddHHmmss")
        $KeyHash = Get-ShortHash -Value $KeyTimestamp
        $KeyName = "$(Get-SafeName -Value $HostAlias)_$KeyHash"
        $KeyPath = Join-Path $SshDir $KeyName
        $IdentityFile = "~/.ssh/$KeyName"
    }

    $PubKeyPath = "$KeyPath.pub"

    if (!(Test-Path $KeyPath)) {
        Write-InfoLine "Creating SSH key: $KeyPath"
        Invoke-NativeCommandLine -FilePath "ssh-keygen" -ArgumentList @("-t", "ed25519", "-a", "100", "-f", $KeyPath, "-N", "", "-C", "$HostAlias ssh key")
    }
    elseif (!(Test-Path $PubKeyPath)) {
        Write-InfoLine "Recreating missing public key: $PubKeyPath"
        $publicKeyText = Invoke-NativeCommandOutput -FilePath "ssh-keygen" -ArgumentList @("-y", "-f", $KeyPath)
        Write-Utf8NoBom -Path $PubKeyPath -Value ($publicKeyText + [Environment]::NewLine)
    }
    else {
        Write-SuccessLine "SSH key pair is available."
    }

    # =========================================================================
    # Section: Configure SSH alias
    # =========================================================================

    Write-Section -Step "4" -Title "Configure SSH Alias"

    Set-ManagedSshHost `
        -ConfigPath $ConfigPath `
        -HostAlias $HostAlias `
        -HostName $RemoteHost `
        -UserName $RemoteUser `
        -IdentityFile $IdentityFile

    Write-SuccessLine "SSH alias '$HostAlias' is configured."

    # =========================================================================
    # Section: Configure ssh-agent
    # =========================================================================

    Write-Section -Step "5" -Title "Configure ssh-agent"

    Invoke-ElevatedSshAgentConfiguration
    Invoke-NativeCommand -FilePath "ssh-add" -ArgumentList @($KeyPath)
    Write-SuccessLine "SSH key added to ssh-agent."

    # =========================================================================
    # Section: Install public key
    # =========================================================================

    Write-Section -Step "6" -Title "Install Public Key"

    $PubKey = (Get-Content $PubKeyPath -Raw).Trim()
    $QuotedPubKey = Convert-ToShellSingleQuoted -Value $PubKey
    $RemoteCommand = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF $QuotedPubKey ~/.ssh/authorized_keys || printf '%s\n' $QuotedPubKey >> ~/.ssh/authorized_keys) && chmod 600 ~/.ssh/authorized_keys"

    Write-InfoLine "Installing public key on remote host."
    Write-WarnLine "You may be asked for the remote account password once."
    Invoke-NativeCommand -FilePath "ssh" -ArgumentList @($HostAlias, $RemoteCommand)

    # =========================================================================
    # Section: Finish
    # =========================================================================

    Write-Section -Step "7" -Title "Finish"
    Write-SuccessLine "SSH key setup complete."
    Write-InfoLine "Test with:"
    Write-Host "ssh $HostAlias"
}
catch {
    Write-FailLine $_.Exception.Message
    Write-Error $_
    exit 1
}
