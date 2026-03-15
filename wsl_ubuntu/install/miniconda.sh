#!/usr/bin/env bash

# =============================================================================
# README - Miniconda installer for WSL Ubuntu
# =============================================================================
#
# Purpose
# -------
# Install Miniconda into the current user's home directory and prepare the base
# environment for later Conda-based workflows.
#
# What it does
# ------------
# - downloads the Miniconda installer for the current CPU architecture
# - installs Miniconda non-interactively into `~/miniconda3`
# - initializes Bash shell support with `conda init bash`
# - updates the Conda base environment through the shared tooling helper
#
# Notes
# -----
# - It is designed to be safe to re-run.
# - If Miniconda is already installed, the installer step is skipped.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/tooling.sh"

# =============================================================================
# Section: Configuration defaults
# =============================================================================

: "${MINICONDA_INSTALL_DIR:=${HOME}/miniconda3}"
: "${MINICONDA_INSTALLER_DIR:=${REPO_ROOT}/zfiles}"
: "${MINICONDA_INIT_SHELL:=bash}"
: "${MINICONDA_X86_64_INSTALLER:=Miniconda3-latest-Linux-x86_64.sh}"
: "${MINICONDA_AARCH64_INSTALLER:=Miniconda3-latest-Linux-aarch64.sh}"
: "${MINICONDA_BASE_URL:=https://repo.anaconda.com/miniconda}"

# =============================================================================
# Section: Internal helpers
# =============================================================================

_detect_miniconda_arch() {
  case "$(uname -m)" in
    x86_64) printf '%s\n' "${MINICONDA_X86_64_INSTALLER}" ;;
    aarch64|arm64) printf '%s\n' "${MINICONDA_AARCH64_INSTALLER}" ;;
    *)
      die "Unsupported architecture for Miniconda installer: $(uname -m)"
      ;;
  esac
}

_is_cached_installer_usable() {
  local installer_path="${1}"

  [ -s "${installer_path}" ] || return 1
  head -n 20 "${installer_path}" | grep -q "Miniconda"
}

# =============================================================================
# Section: Install flow
# =============================================================================

section "Installing Miniconda"

if [ -x "${MINICONDA_INSTALL_DIR}/bin/conda" ]; then
  log "Miniconda is already installed at ${MINICONDA_INSTALL_DIR}"
else
  readonly MINICONDA_INSTALLER_NAME="$(_detect_miniconda_arch)"
  readonly MINICONDA_INSTALLER_PATH="${MINICONDA_INSTALLER_DIR}/${MINICONDA_INSTALLER_NAME}"
  readonly MINICONDA_INSTALLER_URL="${MINICONDA_BASE_URL}/${MINICONDA_INSTALLER_NAME}"

  if _is_cached_installer_usable "${MINICONDA_INSTALLER_PATH}"; then
    log "Using cached Miniconda installer from ${MINICONDA_INSTALLER_DIR}"
  else
    log "Downloading Miniconda installer: ${MINICONDA_INSTALLER_NAME}"
    log "Target cache directory: ${MINICONDA_INSTALLER_DIR}"
  fi

  download_with_cache "${MINICONDA_INSTALLER_PATH}" "${MINICONDA_INSTALLER_URL}" "_is_cached_installer_usable" >/dev/null

  log "Running Miniconda installer"
  bash "${MINICONDA_INSTALLER_PATH}" -b -p "${MINICONDA_INSTALL_DIR}"
fi

log "Initializing Conda for ${MINICONDA_INIT_SHELL}"
"${MINICONDA_INSTALL_DIR}/bin/conda" init "${MINICONDA_INIT_SHELL}" >/dev/null

log "Updating Conda base environment"
CONDA_DEFAULT_BIN="${MINICONDA_INSTALL_DIR}/bin/conda" update_conda_base_environment

success "Miniconda installation complete"
