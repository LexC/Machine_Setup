#!/usr/bin/env bash

# =============================================================================
# README - Shared logging helpers for WSL Ubuntu setup scripts
# =============================================================================
#
# Purpose
# -------
# This file provides a small reusable logging library for the scripts in
# `wsl_ubuntu/`.
#
# It is intended to keep script output:
# - consistent across setup scripts
# - readable during interactive runs
# - configurable for quieter or more verbose execution
#
#
# What this file provides
# -----------------------
# - log levels: DEBUG, INFO, SUCCESS, WARN, ERROR
# - optional ANSI color output
# - simple helper functions for common script patterns
#
#
# Public functions
# ----------------
# - `debug "message"`
# - `info "message"`
# - `log "message"`       # alias for `info`
# - `success "message"`
# - `warn "message"`
# - `err "message"`
# - `die "message"`       # logs an error and exits with code 1
# - `major_section "title"`  # prints a high-visibility section divider
# - `section "title"`     # prints a section divider
#
#
# Environment variables
# ---------------------
# - `LOG_LEVEL`
#     Controls the minimum message level that will be printed.
#     Supported values: DEBUG, INFO, SUCCESS, WARN, ERROR
#     Default: INFO
#
# - `LOG_USE_COLOR`
#     Controls whether ANSI colors are used.
#     Supported values:
#     - auto   -> enable color only when stdout is a terminal
#     - always -> always emit color codes
#     - never  -> never emit color codes
#     Default: auto
#
#
# Usage
# -----
# Source this file from another script:
#
#   readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/utils/log.sh"
#
# Then call:
#
#   section "Installing dependencies"
#   log "Refreshing package metadata"
#   success "Installation complete"
#
# =============================================================================

# =============================================================================
# Section: Source guard
# =============================================================================

if [[ -n "${WSL_UBUNTU_LOG_SH_LOADED:-}" ]]; then
  return 0
fi
readonly WSL_UBUNTU_LOG_SH_LOADED=1

# =============================================================================
# Section: Configuration defaults
# =============================================================================

: "${LOG_LEVEL:=INFO}"
: "${LOG_USE_COLOR:=auto}"

# =============================================================================
# Section: Internal helpers
# =============================================================================

# Convert a log level name into a numeric severity so levels can be compared.
_log_level_value() {
  case "${1^^}" in
    DEBUG) echo 10 ;;
    INFO) echo 20 ;;
    SUCCESS) echo 25 ;;
    WARN) echo 30 ;;
    ERROR) echo 40 ;;
    *) echo 20 ;;
  esac
}

# Decide whether a message should be printed under the current LOG_LEVEL.
_log_should_print() {
  local message_level="${1^^}"
  local configured_level="${LOG_LEVEL^^}"

  [ "$(_log_level_value "${message_level}")" -ge "$(_log_level_value "${configured_level}")" ]
}

# Determine whether ANSI colors should be used for this output stream.
_log_color_enabled() {
  case "${LOG_USE_COLOR}" in
    always) return 0 ;;
    never) return 1 ;;
    auto) [ -t 1 ] ;;
    *) [ -t 1 ] ;;
  esac
}

# Return the ANSI color code associated with a log level.
_log_level_color() {
  case "${1^^}" in
    DEBUG) echo "0;36" ;;
    INFO) echo "1;36" ;;
    SUCCESS) echo "1;32" ;;
    WARN) echo "1;33" ;;
    ERROR) echo "1;31" ;;
    *) echo "0" ;;
  esac
}

# Central output function used by all public log helpers.
_log_emit() {
  local level="${1^^}"
  shift

  _log_should_print "${level}" || return 0

  local message="$*"

  if _log_color_enabled; then
    printf '\n\033[%sm[%s]\033[0m %s\n' \
      "$(_log_level_color "${level}")" \
      "${level}" \
      "${message}"
  else
    printf '\n[%s] %s\n' "${level}" "${message}"
  fi
}

# =============================================================================
# Section: Public logging API
# =============================================================================

debug() {
  _log_emit "DEBUG" "$@"
}

info() {
  _log_emit "INFO" "$@"
}

log() {
  info "$@"
}

success() {
  _log_emit "SUCCESS" "$@"
}

warn() {
  _log_emit "WARN" "$@"
}

err() {
  _log_emit "ERROR" "$@"
}

die() {
  err "$@"
  exit 1
}

# Print a stronger divider for top-level workflow phases.
major_section() {
  local title="$*"

  if _log_color_enabled; then
    printf '\n\033[1;34m################################################################################\033[0m\n'
    printf '\033[1;34m# %s\033[0m\n' "${title}"
    printf '\033[1;34m################################################################################\033[0m\n'
  else
    printf '\n################################################################################\n'
    printf '# %s\n' "${title}"
    printf '################################################################################\n'
  fi
}

# Print a plain section divider for major setup phases.
section() {
  local title="$*"
  printf '\n========== %s ==========\n' "${title}"
}
