#!/usr/bin/env bash

# =============================================================================
# README - Shared shell helpers for WSL Ubuntu setup scripts
# =============================================================================
#
# Purpose
# -------
# This file provides reusable shell-level helpers that are not tied to a
# specific tool or package manager.
#
# Current public functions
# ------------------------
# - `is_blank`
# - `shell_quote`
# - `command_exists`
# - `require_command`
# - `ensure_directory`
# - `file_is_nonempty`
# - `is_interactive_terminal`
# - `require_interactive_terminal`
# - `prompt_yes_no`
# - `validate_wsl`
# - `validate_yes_no`
#
# Notes
# -----
# - This file sources `log.sh` automatically.
# - `validate_yes_no` returns: `0=yes`, `1=no`, `2=invalid`.
#
# =============================================================================

# =============================================================================
# Section: Source guard
# =============================================================================

if [[ -n "${WSL_UBUNTU_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
readonly WSL_UBUNTU_COMMON_SH_LOADED=1

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly COMMON_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_UTILS_DIR}/log.sh"

# =============================================================================
# Section: Internal helpers
# =============================================================================

_classify_yes_no() {
  local answer="${1:-}"

  case "${answer}" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    n|N|no|NO|No)
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

# =============================================================================
# Section: Public common API
# =============================================================================

is_blank() {
  [ -z "${1//[[:space:]]/}" ]
}

shell_quote() {
  printf '%q' "${1}"
}

command_exists() {
  command -v "${1}" >/dev/null 2>&1
}

require_command() {
  local command_name="${1}"

  command_exists "${command_name}" || die "Required command not found: ${command_name}"
}

ensure_directory() {
  mkdir -p "${1}"
}

file_is_nonempty() {
  [ -s "${1}" ]
}

is_interactive_terminal() {
  [ -t 0 ] && [ -t 1 ]
}

require_interactive_terminal() {
  is_interactive_terminal || die "This operation requires an interactive terminal."
}

validate_wsl() {
  grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null
}

validate_yes_no() {
  _classify_yes_no "${1:-}"
}

prompt_yes_no() {
  local prompt_text="${1}"
  local default_answer="${2:-}"
  local answer=""
  local prompt_suffix="[y/n]"
  local validation_status=0

  require_interactive_terminal

  if is_blank "${default_answer}" ; then
    prompt_suffix="[y/n]"
  else
    if _classify_yes_no "${default_answer}"; then
      prompt_suffix="[Y/n]"
    else
      validation_status=$?
      case "${validation_status}" in
        1)
          prompt_suffix="[y/N]"
          ;;
        2)
          die "Unsupported default answer for prompt_yes_no: ${default_answer}"
          ;;
      esac
    fi
  fi

  while true; do
    read -r -p "${prompt_text} ${prompt_suffix} " answer

    if is_blank "${answer}" && [ -n "${default_answer}" ]; then
      answer="${default_answer}"
    fi

    if validate_yes_no "${answer}"; then
      validation_status=0
    else
      validation_status=$?
    fi

    case "${validation_status}" in
      0)
        return 0
        ;;
      1)
        return 1
        ;;
      2)
        warn "Please answer yes or no."
        ;;
    esac
  done
}
