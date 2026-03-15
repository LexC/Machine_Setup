#!/usr/bin/env bash

# =============================================================================
# README - Core WSL Ubuntu setup runner
# =============================================================================
#
# Purpose
# -------
# Run the main install scripts in `wsl_ubuntu/install/` in a fixed order.
#
# What it does
# ------------
# - validates the required install scripts before making system changes
# - runs system update and upgrade at the start
# - runs the Git installer
# - runs the Miniconda installer
# - runs the CUDA WSL installer
# - runs system update and upgrade again at the end
#
# Notes
# -----
# - Run this from the repository's `wsl_ubuntu/` directory structure.
# - It is intended as a convenience wrapper around the dedicated install scripts.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/system.sh"

TASKS=(
  "GIT:${SCRIPT_DIR}/git.sh"
  "MINICONDA:${SCRIPT_DIR}/miniconda.sh"
  "CUDA WSL:${SCRIPT_DIR}/cuda_wsl.sh"
)

# =============================================================================
# Section: Internal helpers
# =============================================================================

# Check that a task script exists before the orchestration loop starts.
require_task_script() {
  local script_path="${1}"

  [ -f "${script_path}" ] || die "Required task script not found: ${script_path}"
}

# Run one setup task in its own Bash process.
run_task() {
  local label="${1}"
  local script_path="${2}"

  major_section "${label}"
  bash "${script_path}"
}

# =============================================================================
# Section: Main
# =============================================================================

main() {
  local task=""
  local label=""
  local script_path=""

  for task in "${TASKS[@]}"; do
    IFS=":" read -r label script_path <<< "${task}"
    require_task_script "${script_path}"
  done

  major_section "Initial System Maintenance"
  update_system_packages
  upgrade_system_packages

  for task in "${TASKS[@]}"; do
    IFS=":" read -r label script_path <<< "${task}"
    run_task "${label}" "${script_path}"
  done

  major_section "Final System Maintenance"
  update_system_packages
  upgrade_system_packages

  success "Core WSL setup run complete"
}

main "$@"
