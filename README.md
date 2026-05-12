# Machine_Setup

Personal machine setup automation for a Windows host and a WSL Ubuntu
environment.

This repository is built around a small set of repeatable entry-point scripts:

- Windows update and package maintenance
- Windows application bootstrap through `winget`
- WSL + Ubuntu installation from Windows
- Ubuntu first-run and day-to-day maintenance inside WSL
- Optional WSL tooling such as Git, Miniconda, CUDA, and a local LLM dev base

The repository is opinionated and personal, but the workflows are simple enough
to adapt to another machine with small configuration changes.

## What Is In This Repo

- `update.py`
  Cross-platform launcher. It dispatches to:
  - `windows/update.ps1` on Windows
  - `wsl_ubuntu/update.sh` on Linux / WSL
- `windows/`
  PowerShell scripts for host-side Windows setup and maintenance.
- `wsl_ubuntu/`
  Bash scripts for Ubuntu-on-WSL setup and maintenance.

## Repository Layout

```text
Machine_Setup/
|- update.py
|- windows/
|  |- update.ps1
|  |- setup_wsl.ps1
|  |- install_system_requirements.ps1
|  |- install_softwares.ps1
|  |- system_info.ps1
|  `- utils/
|- wsl_ubuntu/
   |- update.sh
   |- firstrun.sh
   |- install/
   |  |- all_core.sh
   |  |- git.sh
   |  |- miniconda.sh
   |  |- cuda_wsl.sh
   |  `- setup_wsl_llm_dev.sh
   `- utils/
```

## Requirements

### Windows host

- Windows 10 or Windows 11
- PowerShell or Windows PowerShell
- Administrator rights for system-level setup and update tasks
- Internet access for package downloads, `winget`, WSL installation, and module
  installation

### WSL Ubuntu environment

- Ubuntu installed in WSL
- `bash`
- `sudo` access
- Internet access for `apt`, Miniconda, CUDA repository metadata, and other
  tooling downloads

### Python launcher

`update.py` requires Python 3.

On Linux / WSL, the launcher will create a small `py` wrapper in
`~/.local/bin/py` if the `py` command does not already exist, then prepend that
directory to `PATH` for the current process. That keeps downstream scripts
compatible with a Windows-style `py` command when needed.

## Quick Start

From the repository root:

### Run the platform-native update flow

Windows:

```powershell
py .\update.py
```

WSL / Linux:

```bash
python3 update.py
```

You can also run the platform scripts directly:

Windows:

```powershell
.\windows\update.ps1
```

WSL / Linux:

```bash
bash wsl_ubuntu/update.sh
```

## Windows Workflows

These entry-point scripts are interactive and pause for Enter before exit by
default. `windows/install_system_requirements.ps1` also accepts `-NoPause` when
you do not want that final pause.

### `windows/update.ps1`

Day-to-day Windows maintenance script.

It will:

- elevate to Administrator when needed
- install missing prerequisites through
  `windows/install_system_requirements.ps1`
- install available Windows updates through `PSWindowsUpdate`
- upgrade installed `winget` packages
- warn when Windows reports that a reboot is required

Run it with:

```powershell
.\windows\update.ps1
```

### `windows/install_system_requirements.ps1`

Bootstraps the Windows dependencies used by the rest of the host-side scripts.

It will:

- install `winget` when Microsoft App Installer is missing
- install the `PSWindowsUpdate` module when needed
- import `PSWindowsUpdate` before finishing
- ask you to open a new PowerShell session and rerun the script if a newly
  installed `winget` is not yet visible in the current session

Run it with:

```powershell
.\windows\install_system_requirements.ps1
```

### `windows/install_softwares.ps1`

Installs a personal application list through `winget`.

Default app-list path:

```text
windows/private/windows_apps.psd1
```

Expected file shape:

```powershell
@{
    Apps = @(
        "Vendor.App"
    )
}
```

Behavior notes:

- if `winget` is missing, it first runs
  `windows/install_system_requirements.ps1`
- if the default app-list file does not exist, it prompts once for another
  `.psd1` file
- if the default app-list file exists but is invalid, it is replaced with a new
  empty template at the default path
- if no valid file is provided, it creates an empty template file at the
  default path
- duplicate and empty app IDs are removed before installation

Run it with:

```powershell
.\windows\install_softwares.ps1
```

### `windows/setup_wsl.ps1`

Windows-side bootstrap for WSL and Ubuntu.

It will:

- elevate to Administrator when needed
- install WSL with Ubuntu if WSL is not fully available
- install Ubuntu when WSL exists but no Ubuntu distribution is present
- support `-Action UninstallDistros` to unregister all WSL distros
- support `-Action UninstallWsl` to unregister all distros, disable WSL
  features, and remove the WSL app package
- avoid destructive behavior if WSL and Ubuntu are already installed

Run it from Command Prompt or PowerShell:

```bat
powershell -ExecutionPolicy Bypass -File .\windows\setup_wsl.ps1
```

Examples:

```powershell
.\windows\setup_wsl.ps1
.\windows\setup_wsl.ps1 -Action UninstallDistros
.\windows\setup_wsl.ps1 -Action UninstallWsl
```

## WSL Ubuntu Workflows

### `wsl_ubuntu/firstrun.sh`

Intended for a fresh Ubuntu install inside WSL.

It will:

- refresh package metadata
- run a `full-upgrade`
- install `build-essential`

Run it with:

```bash
bash wsl_ubuntu/firstrun.sh
```

### `wsl_ubuntu/update.sh`

Normal day-to-day maintenance inside WSL Ubuntu.

It will:

- refresh `apt` metadata
- upgrade installed Ubuntu packages
- update the Conda base environment when Conda is present

Run it with:

```bash
bash wsl_ubuntu/update.sh
```

### `wsl_ubuntu/install/all_core.sh`

Convenience wrapper for the main WSL install sequence.

It runs, in order:

- Ubuntu package maintenance
- `wsl_ubuntu/install/git.sh`
- `wsl_ubuntu/install/miniconda.sh`
- `wsl_ubuntu/install/cuda_wsl.sh`
- final Ubuntu package maintenance

This wrapper is opinionated: it always includes the CUDA WSL installer. Use it
when you want the full Git + Miniconda + CUDA sequence. If you do not want CUDA
or the machine is not an NVIDIA-capable WSL setup, run the install scripts
under `wsl_ubuntu/install/` individually instead.

Because this wrapper runs `git.sh`, be ready to provide your Git user name and
email on first run if they are not already configured.

Run it with:

```bash
bash wsl_ubuntu/install/all_core.sh
```

### `wsl_ubuntu/install/git.sh`

Installs Git and configures the current user's global Git identity.

Behavior notes:

- may prompt for your Git user name and email on first run
- non-interactive runs require that Git identity values are already configured
  locally before you run the script

Run it with:

```bash
bash wsl_ubuntu/install/git.sh
```

### `wsl_ubuntu/install/miniconda.sh`

Installs Miniconda for the current user into `~/miniconda3`, initializes Bash,
and updates the Conda base environment.

Run it with:

```bash
bash wsl_ubuntu/install/miniconda.sh
```

### `wsl_ubuntu/install/cuda_wsl.sh`

Installs the NVIDIA CUDA toolkit inside Ubuntu running on WSL.

Behavior notes:

- designed for Ubuntu on WSL, not a standard Linux desktop
- configures NVIDIA's WSL CUDA repository
- installs either the latest CUDA toolkit or a requested major.minor version
- updates `~/.bashrc` with a managed CUDA `PATH` block
- does not install an NVIDIA Linux driver inside WSL

Examples:

```bash
bash wsl_ubuntu/install/cuda_wsl.sh
```

```bash
bash wsl_ubuntu/install/cuda_wsl.sh 12.8
```

### `wsl_ubuntu/install/setup_wsl_llm_dev.sh`

Sets up a clean Ubuntu-on-WSL foundation for later local LLM work.

It focuses on:

- distro updates
- common development packages
- Python and virtual environment support
- a clean workspace under `~/dev/llm/`
- a reusable base virtual environment
- environment checks such as `systemd` and `nvidia-smi` visibility

It intentionally does not install Ollama, `llama.cpp`, CUDA drivers, or any
models.

Run it with:

```bash
bash wsl_ubuntu/install/setup_wsl_llm_dev.sh
```

## Suggested Usage Pattern

For a new Windows machine:

1. Run `windows/setup_wsl.ps1` if WSL + Ubuntu are not installed yet.
2. Run `windows/install_system_requirements.ps1`.
3. Create or supply `windows/private/windows_apps.psd1`.
4. Run `windows/install_softwares.ps1`.
5. Use `windows/update.ps1` for ongoing Windows maintenance.

For a new Ubuntu distribution inside WSL:

1. Run `wsl_ubuntu/firstrun.sh`.
2. Run `wsl_ubuntu/install/all_core.sh` only if you want the opinionated
   Git + Miniconda + CUDA setup sequence on an NVIDIA-capable WSL machine.
3. Otherwise, run the scripts under `wsl_ubuntu/install/` selectively.
4. Run `wsl_ubuntu/install/setup_wsl_llm_dev.sh` if this machine is meant for
   local LLM development.
5. Use `wsl_ubuntu/update.sh` for ongoing maintenance.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
