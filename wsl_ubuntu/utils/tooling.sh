#!/usr/bin/env bash

# =============================================================================
# README - Shared user-space tooling helpers for WSL Ubuntu setup scripts
# =============================================================================
#
# Purpose
# -------
# This file provides reusable helper functions for non-system tools managed in
# user space, such as Conda and future developer tooling.
#
# Current public functions
# ------------------------
# - `is_interactive_terminal`
# - `resolve_downloader`
# - `download_with_cache`
# - `update_conda_base_environment`
#
# Notes
# -----
# - This file sources `log.sh` and `common.sh` automatically.
# - It can resolve tools from PATH or from configured fallback locations.
#
# =============================================================================

# =============================================================================
# Section: Source guard
# =============================================================================

if [[ -n "${WSL_UBUNTU_TOOLING_SH_LOADED:-}" ]]; then
  return 0
fi
readonly WSL_UBUNTU_TOOLING_SH_LOADED=1

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly TOOLING_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TOOLING_UTILS_DIR}/log.sh"
# shellcheck disable=SC1091
source "${TOOLING_UTILS_DIR}/common.sh"

# =============================================================================
# Section: General tooling helpers
# =============================================================================

_resolve_tool_command() {
  local command_name="${1}"
  local fallback_path="${2:-}"

  if command -v "${command_name}" >/dev/null 2>&1; then
    command -v "${command_name}"
    return 0
  fi

  if [ -n "${fallback_path}" ] && [ -x "${fallback_path}" ]; then
    printf '%s\n' "${fallback_path}"
    return 0
  fi

  return 1
}

resolve_downloader() {
  if command -v curl >/dev/null 2>&1; then
    printf '%s\n' "curl"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    printf '%s\n' "wget"
    return 0
  fi

  die "Neither curl nor wget is available for downloads."
}

download_with_cache() {
  local target_path="${1}"
  local source_url="${2}"
  local validator_func="${3:-}"
  local downloader=""

  mkdir -p "$(dirname "${target_path}")"

  if [ -n "${validator_func}" ]; then
    if "${validator_func}" "${target_path}"; then
      printf '%s\n' "${target_path}"
      return 0
    fi
  elif [ -s "${target_path}" ]; then
    printf '%s\n' "${target_path}"
    return 0
  fi

  if [ -e "${target_path}" ]; then
    rm -f "${target_path}"
  fi

  downloader="$(resolve_downloader)"
  case "${downloader}" in
    curl)
      curl -fsSL "${source_url}" -o "${target_path}"
      ;;
    wget)
      wget -O "${target_path}" "${source_url}"
      ;;
  esac

  if [ -n "${validator_func}" ]; then
    if ! "${validator_func}" "${target_path}"; then
      die "Downloaded file failed validation: ${target_path}"
    fi
  elif [ ! -s "${target_path}" ]; then
    die "Downloaded file is empty: ${target_path}"
  fi

  printf '%s\n' "${target_path}"
}

# =============================================================================
# Section: Conda
# =============================================================================

# Default fallback location for a standard Miniconda installation.
: "${CONDA_DEFAULT_BIN:=${HOME}/miniconda3/bin/conda}"
_resolve_conda_command() {
  _resolve_tool_command "conda" "${CONDA_DEFAULT_BIN}"
}


# Update the Conda base environment when Conda is available on PATH or in the
# default Miniconda installation location.
update_conda_base_environment() {
  local conda_cmd=""

  if ! conda_cmd="$(_resolve_conda_command)"; then
    warn "Conda was not found. Skipping Conda base environment update."
    return 0
  fi

  section "Updating Conda base environment"

  log "Using Conda executable: ${conda_cmd}"
  "${conda_cmd}" update -n base -c defaults conda -y
  "${conda_cmd}" update -n base --all -y

  success "Conda base environment update complete"
}
