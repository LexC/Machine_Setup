#!/usr/bin/env bash
# =============================================================================
# README - Everyday Ubuntu update for WSL
# =============================================================================
#
# Purpose
# -------
# Run this for normal day-to-day system maintenance in WSL.
#
# What it does
# ------------
# - refreshing apt package metadata
# - running the default package `upgrade`
# - updating the Conda base environment when Conda is installed
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
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/utils/tooling.sh"

# =============================================================================
# Section: System maintenance
# =============================================================================

update_system_packages
upgrade_system_packages
update_conda_base_environment
