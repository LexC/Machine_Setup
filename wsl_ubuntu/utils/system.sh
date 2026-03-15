#!/usr/bin/env bash

# =============================================================================
# README - Shared system helpers for WSL Ubuntu setup scripts
# =============================================================================
#
# Purpose
# -------
# This file provides reusable system-level helper functions for scripts in
# `wsl_ubuntu/`.
#
# Current public functions
# ------------------------
# - `update_system_packages`
# - `upgrade_system_packages [upgrade|full-upgrade|dist-upgrade]`
# - `refresh_and_upgrade_system_packages [upgrade|full-upgrade|dist-upgrade]`
#
# Usage
# -----
# Source this file from another script:
#
#   readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/utils/system.sh"
#
# Then call:
#
#   update_system_packages
#   upgrade_system_packages
#   refresh_and_upgrade_system_packages
#
# Notes
# -----
# - This file sources `log.sh` automatically.
# - `update_system_packages` refreshes package metadata only.
# - The default upgrade action is `upgrade`.
#
# =============================================================================

# =============================================================================
# Section: Source guard
# =============================================================================

if [[ -n "${WSL_UBUNTU_SYSTEM_SH_LOADED:-}" ]]; then
  return 0
fi
readonly WSL_UBUNTU_SYSTEM_SH_LOADED=1

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SYSTEM_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SYSTEM_UTILS_DIR}/log.sh"

# =============================================================================
# Section: Configuration defaults
# =============================================================================

: "${APT_RETRY_COUNT:=3}"
: "${APT_LOCK_TIMEOUT:=60}"

# =============================================================================
# Section: Public system API
# =============================================================================

# Refresh package metadata and verify that the local package database is in a
# healthy state before any upgrades are attempted later.
update_system_packages() {
  section "Updating Ubuntu package metadata"

  log "Refreshing sudo credentials"
  sudo -v

  log "Refreshing apt package metadata with retry support"
  sudo apt-get \
    -o Acquire::Retries="${APT_RETRY_COUNT}" \
    -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
    update

  log "Checking package database consistency"
  sudo apt-get \
    -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
    check

  success "Ubuntu package metadata refresh complete"
}

# Upgrade installed packages in a non-interactive way, then remove packages and
# archives that are no longer useful for a normal day-to-day environment.
upgrade_system_packages() {
  local upgrade_action="${1:-upgrade}"

  case "${upgrade_action}" in
    upgrade|full-upgrade|dist-upgrade) ;;
    *)
      die "Unsupported upgrade action: ${upgrade_action}"
      ;;
  esac

  section "Upgrading installed Ubuntu packages"

  log "Applying package upgrades with apt-get ${upgrade_action}"
  sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get \
    -o Acquire::Retries="${APT_RETRY_COUNT}" \
    -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    "${upgrade_action}" -y

  log "Removing packages that are no longer required"
  sudo DEBIAN_FRONTEND=noninteractive apt-get \
    -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
    autoremove -y

  log "Cleaning obsolete downloaded package archives"
  sudo apt-get \
    -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
    autoclean

  success "Ubuntu package update complete"
}

# Run the normal full maintenance flow: refresh metadata first, then upgrade the
# currently installed packages using the requested upgrade mode.
refresh_and_upgrade_system_packages() {
  local upgrade_action="${1:-upgrade}"

  update_system_packages
  upgrade_system_packages "${upgrade_action}"
}
