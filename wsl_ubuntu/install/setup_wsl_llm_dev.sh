#!/usr/bin/env bash
#
# =============================================================================
# README — WSL Ubuntu foundation setup for local LLM coding
# =============================================================================
#
# Purpose
# -------
# This script prepares a WSL Ubuntu distribution to become a clean development
# environment for local LLM work, especially for a future stack such as:
#
#   Python + Ollama + llama.cpp + Llama-family models
#
# The script does NOT install Ollama, llama.cpp, CUDA, or any LLM model yet.
# Instead, it prepares the Linux foundation that those tools will depend on.
#
#
# What this script does
# ---------------------
# 1. Verifies basic execution context
#    - Checks whether the environment appears to be WSL
#    - Confirms that `sudo` is available
#
# 2. Updates the Ubuntu distribution
#    - Refreshes apt package metadata
#    - Upgrades installed Ubuntu packages
#    - Does not update Conda or other user-space package managers
#
# 3. Installs base development tools
#    - Build tools for native software compilation
#    - Git / curl / wget and other common CLI tools
#    - Python 3, pip, and virtual environment support
#    - OpenBLAS development headers for future CPU-accelerated builds
#
# 4. Creates a clean local workspace
#    - ~/dev/llm/projects
#    - ~/dev/llm/models
#    - ~/dev/llm/venvs
#
# 5. Creates a base Python virtual environment
#    - Builds a reusable Python environment for future local LLM projects
#    - Updates pip / setuptools / wheel inside it
#
# 6. Performs environment checks
#    - Checks whether systemd is enabled
#    - Checks whether `nvidia-smi` is visible from inside WSL
#
# 7. Prints a compact environment summary
#    - Kernel
#    - Distro name
#    - Python version
#    - CMake version
#    - Git version
#    - Workspace root
#
#
# What this script does NOT do
# ----------------------------
# This script intentionally does not:
#
# - install Ollama
# - install llama.cpp
# - pull any Llama model
# - configure CUDA manually
# - create agent, RAG, or vector database tooling
#
# Those belong to the next setup phases.
#
#
# Why this separation is useful
# -----------------------------
# Keeping the "Linux foundation" separate from the "LLM runtime" setup makes the
# environment easier to debug and maintain.
#
# If something fails later, you can distinguish between:
# - distro / package / Python issues
# - GPU visibility issues
# - Ollama installation issues
# - llama.cpp build issues
# - model/runtime issues
#
#
# Expected next steps after this script
# -------------------------------------
# After this foundation script succeeds, the normal next steps are:
#
# 1. Install Ollama
# 2. Validate Ollama locally
# 3. Install or build llama.cpp
# 4. Download or load a Llama-family model
# 5. Connect to the local model from Python
#
#
# Usage
# -----
# Run this from a checkout of this repository. The script expects to remain in:
#
#   wsl_ubuntu/install/setup_wsl_llm_dev.sh
#
# From the repository root, run:
#
#   bash wsl_ubuntu/install/setup_wsl_llm_dev.sh
#
# Or from inside `wsl_ubuntu/install/`:
#
#   chmod +x setup_wsl_llm_dev.sh
#   ./setup_wsl_llm_dev.sh
#
#
# Notes
# -----
# - This script is designed for Ubuntu running inside WSL.
# - This script is not standalone; it depends on shared helpers in
#   `wsl_ubuntu/utils/`.
# - It is safe to re-run in normal circumstances.
# - Some steps may do little or nothing on subsequent runs if the packages,
#   folders, or virtual environment already exist.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
readonly WSL_UBUNTU_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly LOG_UTILS_SCRIPT="${WSL_UBUNTU_ROOT}/utils/log.sh"
readonly COMMON_UTILS_SCRIPT="${WSL_UBUNTU_ROOT}/utils/common.sh"
readonly SYSTEM_UTILS_SCRIPT="${WSL_UBUNTU_ROOT}/utils/system.sh"

if [ ! -f "${LOG_UTILS_SCRIPT}" ]; then
  printf '[ERROR] Expected shared helper script at %s\n' "${LOG_UTILS_SCRIPT}" >&2
  printf '[ERROR] Run this script from the repository checkout and keep it under wsl_ubuntu/install/.\n' >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${LOG_UTILS_SCRIPT}"
# shellcheck disable=SC1091
for helper_script in "${COMMON_UTILS_SCRIPT}" "${SYSTEM_UTILS_SCRIPT}"; do
  if [ ! -f "${helper_script}" ]; then
    die "Expected shared helper script at ${helper_script}. Run this script from the repository checkout and keep it under wsl_ubuntu/install/."
  fi
done

# shellcheck disable=SC1091
source "${COMMON_UTILS_SCRIPT}"
# shellcheck disable=SC1091
source "${SYSTEM_UTILS_SCRIPT}"

# =============================================================================
# Section: Environment checks
# =============================================================================

has_systemd() {
  # systemd is PID 1 when enabled in WSL
  [ "$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ')" = "systemd" ]
}

package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

check_runtime_context() {
  require_command sudo

  if validate_wsl; then
    log "WSL environment detected."
  else
    warn "This does not look like WSL. The script can still run, but it was designed for WSL Ubuntu."
  fi
}

# =============================================================================
# Section: Configuration
# =============================================================================

readonly WORKROOT="${HOME}/dev/llm"
readonly PROJECTS="${WORKROOT}/projects"
readonly MODELS="${WORKROOT}/models"
readonly VENVS="${WORKROOT}/venvs"
readonly BASE_VENV="${VENVS}/base"

BASE_PACKAGES=(
  build-essential
  cmake
  ninja-build
  pkg-config
  git
  curl
  wget
  unzip
  zip
  ca-certificates
  software-properties-common
  htop
  tree
  jq
  python3
  python3-dev
  python3-pip
  python3-venv
  pipx
  libopenblas-dev
)

# =============================================================================
# Section: Setup steps
# =============================================================================

enter_script_directory() {
  log "Switching to the script directory..."
  cd "${SCRIPT_DIR}"
}

refresh_system_packages() {
  refresh_and_upgrade_system_packages
}

install_base_packages() {
  local missing_packages=()
  local package

  for package in "${BASE_PACKAGES[@]}"; do
    if ! package_installed "${package}"; then
      missing_packages+=("${package}")
    fi
  done

  if [ "${#missing_packages[@]}" -eq 0 ]; then
    log "Base packages are already installed."
  else
    log "Installing missing base packages for LLM development..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get \
      -o Acquire::Retries="${APT_RETRY_COUNT}" \
      -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
      install -y "${missing_packages[@]}"
  fi

  log "Ensuring pipx is on PATH for the current user..."
  python3 -m pipx ensurepath || true
}

create_workspace() {
  local workspace_dir

  log "Creating workspace folders..."
  for workspace_dir in "${PROJECTS}" "${MODELS}" "${VENVS}"; do
    ensure_directory "${workspace_dir}"
  done
}

setup_base_venv() {
  if [ ! -d "${BASE_VENV}" ]; then
    log "Creating a base Python virtual environment..."
    python3 -m venv "${BASE_VENV}"
  fi

  log "Upgrading pip/setuptools/wheel inside the base venv..."
  # shellcheck disable=SC1091
  source "${BASE_VENV}/bin/activate"
  python -m pip install --upgrade pip setuptools wheel
  deactivate
}

# =============================================================================
# Section: Post-setup checks
# =============================================================================

check_systemd_status() {
  log "Checking systemd status..."

  if has_systemd; then
    log "systemd is enabled in this distro."
    return
  fi

  warn "systemd does NOT appear to be enabled."
  warn "If you want Ollama to run as a service in WSL, enable systemd in /etc/wsl.conf:"
  cat <<'EOF'
[boot]
systemd=true
EOF
  warn "Then from Windows PowerShell run: wsl --shutdown"
}

check_gpu_visibility() {
  log "Checking NVIDIA GPU visibility from inside WSL..."

  if command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi works inside WSL. GPU path looks available."
    nvidia-smi || true
    return
  fi

  warn "nvidia-smi is not working inside WSL."
  warn "Before installing local LLM runtimes, fix Windows NVIDIA driver / WSL GPU integration."
}

print_environment_summary() {
  log "Collecting a short environment summary..."
  echo "----------------------------------------"
  echo "Kernel:   $(uname -r)"
  echo "Distro:   $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
  echo "Python:   $(python3 --version)"
  echo "CMake:    $(cmake --version | head -n 1)"
  echo "Git:      $(git --version)"
  echo "Workspace:${WORKROOT}"
  echo "----------------------------------------"
}

# =============================================================================
# Section: Main entrypoint
# =============================================================================

main() {
  log "Starting WSL Ubuntu LLM dev environment bootstrap..."

  enter_script_directory
  check_runtime_context
  refresh_system_packages
  install_base_packages
  create_workspace
  setup_base_venv
  check_systemd_status
  check_gpu_visibility
  print_environment_summary

  log "Done."
  log "Next logical step: install Ollama, then add llama.cpp, then test a Llama-family model."
}

main "$@"
