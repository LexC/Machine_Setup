@echo off
setlocal EnableDelayedExpansion
REM =============================================================================
REM README - WSL Ubuntu setup
REM =============================================================================
REM
REM Purpose
REM -------
REM Installs Windows Subsystem for Linux and an Ubuntu distribution.
REM
REM Default behavior
REM ----------------
REM - Re-launches itself with administrator rights when needed
REM - Installs WSL with Ubuntu when WSL is not fully available
REM - Installs Ubuntu separately when WSL is already available but no Ubuntu
REM   distribution is installed yet
REM - Keeps the workflow non-destructive when WSL and Ubuntu are already present
REM
REM Example:
REM   wsl_setup.bat
REM
REM Notes
REM -----
REM - This script is intended for Windows Command Prompt
REM - Internet access may be required for the WSL or Ubuntu installation
REM - A reboot may be required before the Ubuntu distribution is fully usable
REM
REM =============================================================================

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set /a SECTION_NUMBER=-1
set "REBOOT_NOTICE_REQUIRED="

call :NextSection "WSL Ubuntu Setup"
call :Info "Starting WSL setup workflow."

REM =============================================================================
REM Section: Administrator elevation
REM =============================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    call :NextSection "Administrator Elevation"
    call :Warn "Administrator privileges are required."
    call :Info "Attempting to re-launch with elevated rights."
    if not exist "%POWERSHELL_EXE%" (
        call :Error "PowerShell was not found for automatic elevation."
        call :Warn "Please re-run this file as Administrator."
        pause
        exit /b 1
    )
    "%POWERSHELL_EXE%" -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs | Out-Null; exit 0 } catch { exit 1 }"
    set "ELEVATION_EXIT=!errorlevel!"
    if not "!ELEVATION_EXIT!"=="0" (
        call :Error "Automatic elevation failed."
        call :Warn "Please re-run this file as Administrator."
        pause
        exit /b 1
    )
    call :Success "Elevated copy started successfully."
    exit /b 0
)

REM =============================================================================
REM Section: WSL installation
REM =============================================================================

call :NextSection "Install WSL"

wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    call :Info "WSL is not fully available. Installing WSL with Ubuntu."
    wsl --install -d Ubuntu
    set "WSL_INSTALL_EXIT=!errorlevel!"
    if not "!WSL_INSTALL_EXIT!"=="0" (
        call :Error "WSL installation failed."
        pause
        exit /b 1
    )
    set "REBOOT_NOTICE_REQUIRED=1"
    goto finish
)

call :Success "WSL is available."

REM =============================================================================
REM Section: Ubuntu installation
REM =============================================================================

call :NextSection "Install Ubuntu"

wsl --list --quiet | find /i "Ubuntu" >nul
if %errorlevel% neq 0 (
    call :Info "Ubuntu distribution not found. Installing Ubuntu."
    set "UBUNTU_INSTALL_LOG=%TEMP%\wsl_ubuntu_install_%RANDOM%.log"
    wsl --install -d Ubuntu > "!UBUNTU_INSTALL_LOG!" 2>&1
    set "UBUNTU_INSTALL_EXIT=!errorlevel!"
    type "!UBUNTU_INSTALL_LOG!"
    if not "!UBUNTU_INSTALL_EXIT!"=="0" (
        set "UBUNTU_ALREADY_EXISTS="
        find /i "ERROR_ALREADY_EXISTS" "!UBUNTU_INSTALL_LOG!" >nul && set "UBUNTU_ALREADY_EXISTS=1"
        find /i "already exists" "!UBUNTU_INSTALL_LOG!" >nul && set "UBUNTU_ALREADY_EXISTS=1"
        if defined UBUNTU_ALREADY_EXISTS (
            call :Warn "Ubuntu distribution already exists."
        ) else (
            call :Error "Ubuntu installation failed."
            del /q "!UBUNTU_INSTALL_LOG!" >nul 2>&1
            pause
            exit /b 1
        )
    ) else (
        set "REBOOT_NOTICE_REQUIRED=1"
    )
    del /q "!UBUNTU_INSTALL_LOG!" >nul 2>&1
) else (
    call :Success "Ubuntu is already installed."
)

:finish
REM =============================================================================
REM Section: Finish
REM =============================================================================

call :NextSection "Finish"
call :Success "WSL setup workflow complete."
if defined REBOOT_NOTICE_REQUIRED (
    call :Warn "A reboot may still be required before Ubuntu is ready."
)
pause
exit /b 0

:NextSection
set /a SECTION_NUMBER+=1
call :Section "!SECTION_NUMBER!" "%~1"
exit /b 0

:Section
echo.
echo [%~1] %~2
echo.
exit /b 0

:Info
echo [INFO] %~1
exit /b 0

:Success
echo [ OK ] %~1
exit /b 0

:Warn
echo [WARN] %~1
exit /b 0

:Error
echo [FAIL] %~1
exit /b 0
