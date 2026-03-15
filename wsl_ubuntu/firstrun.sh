#!/usr/bin/env bash
# =============================================================================
# README - First-run Ubuntu bootstrap for WSL
# =============================================================================
#
# Purpose
# -------
# Run this soon after a fresh Ubuntu installation in WSL.
#
# What it does
# ------------
# - refreshing apt package metadata
# - running a first-run `full-upgrade`
# - installing `build-essential`
#
# Notes
# -----
# - Run it from this repository's `wsl_ubuntu/` directory structure.
# - It is designed to be safe to re-run.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/utils/system.sh"

# =============================================================================
# Section: System bootstrap
# =============================================================================

update_system_packages
upgrade_system_packages full-upgrade

# Install the base compiler toolchain required by many later setup steps.
section "Installing base build tools"
log "Installing base build tools"
sudo DEBIAN_FRONTEND=noninteractive apt-get \
  -o Acquire::Retries="${APT_RETRY_COUNT}" \
  -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
  install -y build-essential

success "First-run bootstrap complete"
