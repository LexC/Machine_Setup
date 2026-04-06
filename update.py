#!/usr/bin/env python3
""" README
Cross-platform update launcher.

Routes this repository's update command to the platform-native script:
- `windows/update.ps1` on Windows
- `wsl_ubuntu/update.sh` on Linux / WSL
"""

from __future__ import annotations

#%% === Libraries ===
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


#%% === General Tools ===
# ---------- Variables ----------
def global_variables() -> dict[str, Path | dict[str, Path | tuple[str, ...]]]:
    """
    Defines and returns the shared configuration used by the launcher.

    Returns:
        dict[str, Path | dict[str, Path | tuple[str, ...]]]: Repository paths
            and per-platform executable search order.
    """
    repo_root = Path(__file__).resolve().parent

    return {
        "repo_root": repo_root,
        "windows": {
            "update_script": repo_root / "windows" / "update.ps1",
            "execution_candidates": (
                "pwsh.exe",
                "powershell.exe",
                "pwsh",
                "powershell",
            ),
        },
        "linux": {
            "update_script": repo_root / "wsl_ubuntu" / "update.sh",
            "execution_candidates": ("bash",),
        },
    }


VAR = global_variables()

# ---------- Support functions ----------
def message_fail(message: str) -> int:
    """
    Prints a failure message and returns a non-zero exit code.

    Args:
        message (str): Error text to display to stderr.

    Returns:
        int: Exit code for failed execution.
    """
    print(f"[FAIL] {message}", file=sys.stderr)
    return 1


def find_system() -> str:
    """
    Validates and returns the current operating system name.

    Returns:
        str: Supported platform name.

    Raises:
        ValueError: Raised when the current platform is not supported.
    """
    system = platform.system().lower()
    supported_systems = {"windows", "linux"}
    if system not in supported_systems:
        raise ValueError(
            f"Unsupported operating system: {system}. "
            "This launcher supports Windows and Linux/WSL."
        )

    return system


def setup_linux_py_alias() -> None:
    """
    Ensures Linux has a `py` command available before running the update flow.

    Creates a small wrapper script in `~/.local/bin/py` when `py` is missing
    and prepends that directory to PATH for the current process. Existing
    user-managed files are preserved.

    Raises:
        FileNotFoundError: Raised when no Python interpreter is available to
            back the `py` command.
        OSError: Raised when the wrapper script cannot be created or a
            conflicting non-file path already exists.
    """

    # --- SETUP AND VALIDATION ---
    if shutil.which("py"):
        return

    alias_dir = Path.home() / ".local" / "bin"
    alias_path = alias_dir / "py"
    alias_dir_str = str(alias_dir)
    current_path = os.environ.get("PATH", "")
    path_entries = current_path.split(os.pathsep) if current_path else []

    path_exists = alias_path.exists() or alias_path.is_symlink()
    if path_exists:
        if alias_path.is_file() and not alias_path.is_symlink():
            if alias_dir_str not in path_entries:
                os.environ["PATH"] = (
                    f"{alias_dir_str}{os.pathsep}{current_path}"
                    if current_path
                    else alias_dir_str
                )
            return

        raise OSError(
            f"Cannot create Linux `py` alias because {alias_path} already exists "
            "and is not a regular file."
        )

    python_executable = shutil.which("python3") or shutil.which("python")
    if not python_executable:
        raise FileNotFoundError(
            "Could not find python3 or python to create the Linux `py` alias."
        )

    # --- LOGIC ---
    alias_dir.mkdir(parents=True, exist_ok=True)
    alias_path.write_text(
        f'#!/usr/bin/env bash\nexec "{python_executable}" "$@"\n',
        encoding="utf-8",
    )
    alias_path.chmod(0o755)

    if alias_dir_str not in path_entries:
        os.environ["PATH"] = (
            f"{alias_dir_str}{os.pathsep}{current_path}"
            if current_path
            else alias_dir_str
        )


#%% === Show Time ===
def main() -> int:
    """
    Finds the current platform and runs its update script.

    Returns:
        int: Exit code returned by the selected update flow.
    """

    # --- SETUP AND VALIDATION ---
    system = find_system()
    platform_config = VAR[system]
    script_path = platform_config["update_script"]
    executable_candidates = platform_config["execution_candidates"]

    if system == "windows":
        executable_arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
        missing_executable_message = (
            "Could not find PowerShell. Install PowerShell or run "
            "windows/update.ps1 directly."
        )
    else:
        executable_arguments = []
        missing_executable_message = (
            "Could not find bash. Install bash or run wsl_ubuntu/update.sh directly."
        )

    if not script_path.is_file():
        raise FileNotFoundError(f"Expected script at {script_path}")

    executable = None
    for candidate in executable_candidates:
        executable = shutil.which(candidate)
        if executable:
            break

    if not executable:
        return message_fail(missing_executable_message)

    if system == "linux":
        setup_linux_py_alias()

    # --- LOGIC ---
    command = [executable, *executable_arguments, str(script_path), *sys.argv[1:]]

    # --- RETURN ---
    return subprocess.run(command, cwd=VAR["repo_root"]).returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (FileNotFoundError, OSError, ValueError) as exc:
        sys.exit(message_fail(str(exc)))
