#!/usr/bin/env bash

# =============================================================================
# README - Git installer and configuration for WSL Ubuntu
# =============================================================================
#
# Purpose
# -------
# Install Git and configure the current user's global Git identity.
#
# What it does
# ------------
# - installs Git through apt
# - loads private Git identity settings from `wsl_ubuntu/private/git_config.sh`
# - prompts for missing values if the private file is not filled in yet
#
# Notes
# -----
# - Private values are expected to live in the ignored `private/` directory.
# - It is designed to be safe to re-run.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PRIVATE_GIT_CONFIG="${REPO_ROOT}/private/git_config.sh"
readonly PRIVATE_DIR="$(dirname "${PRIVATE_GIT_CONFIG}")"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/tooling.sh"

# =============================================================================
# Section: Configuration defaults
# =============================================================================

: "${GIT_DEFAULT_BRANCH:=main}"

# =============================================================================
# Section: Private configuration
# =============================================================================

if [ -f "${PRIVATE_GIT_CONFIG}" ]; then
  # shellcheck disable=SC1091
  source "${PRIVATE_GIT_CONFIG}"
fi

: "${GIT_USER_NAME:=}"
: "${GIT_USER_EMAIL:=}"

# =============================================================================
# Section: Internal helpers
# =============================================================================

_write_private_git_config() {
  ensure_directory "${PRIVATE_DIR}"

  {
    printf '%s\n' '# Private Git identity configuration for WSL Ubuntu setup scripts.'
    printf '%s\n' '#'
    printf '%s\n' '# This file is intentionally stored under `wsl_ubuntu/private/`, which is'
    printf '%s\n' '# ignored by git in this repository.'
    printf '\n'
    printf 'GIT_USER_NAME=%s\n' "$(shell_quote "${GIT_USER_NAME}")"
    printf 'GIT_USER_EMAIL=%s\n' "$(shell_quote "${GIT_USER_EMAIL}")"
    printf 'GIT_DEFAULT_BRANCH=%s\n' "$(shell_quote "${GIT_DEFAULT_BRANCH}")"
  } > "${PRIVATE_GIT_CONFIG}"
}

_prompt_for_missing_git_identity() {
  if is_blank "${GIT_USER_NAME}"; then
    prompt_required_value "Enter your Git user name" GIT_USER_NAME "Git user name is required."
  fi

  if is_blank "${GIT_USER_EMAIL}"; then
    prompt_required_value "Enter your Git user email" GIT_USER_EMAIL "Git user email is required."
  fi
}

_ensure_private_git_config() {
  if [ -f "${PRIVATE_GIT_CONFIG}" ]; then
    return 0
  fi

  GIT_USER_NAME=""
  GIT_USER_EMAIL=""
  _write_private_git_config

  if ! is_interactive_terminal; then
    die "Created ${PRIVATE_GIT_CONFIG} with blank values. Fill in GIT_USER_NAME and GIT_USER_EMAIL, then run this script again."
  fi

  log "Private Git config not found. Collecting values interactively."
  _prompt_for_missing_git_identity

  if is_blank "${GIT_USER_NAME}" || is_blank "${GIT_USER_EMAIL}"; then
    die "Git user name and email are required."
  fi

  _write_private_git_config
  success "Saved private Git config to ${PRIVATE_GIT_CONFIG}"
}

_ensure_git_identity_values() {
  if is_blank "${GIT_USER_NAME}" || is_blank "${GIT_USER_EMAIL}"; then
    if ! is_interactive_terminal; then
      die "Git identity is missing in ${PRIVATE_GIT_CONFIG}. Update GIT_USER_NAME and GIT_USER_EMAIL, then run this script again."
    fi

    log "Private Git config is incomplete. Collecting missing values interactively."
    _prompt_for_missing_git_identity
    _write_private_git_config
    success "Updated private Git config at ${PRIVATE_GIT_CONFIG}"
  fi

  if is_blank "${GIT_USER_NAME}" || is_blank "${GIT_USER_EMAIL}"; then
    die "Git user name and email must not be blank."
  fi
}

_set_git_global_if_missing() {
  local key="${1}"
  local value="${2}"
  local current_value=""

  current_value="$(git config --global --get "${key}" || true)"
  if is_blank "${current_value}"; then
    git config --global "${key}" "${value}"
  fi
}

_git_user_identity_needs_configuration() {
  local user_name=""
  local user_email=""

  user_name="$(git config --global --get user.name || true)"
  user_email="$(git config --global --get user.email || true)"

  if is_blank "${user_name}" || is_blank "${user_email}"; then
    return 0
  fi

  return 1
}

_git_default_branch_needs_configuration() {
  local default_branch=""

  default_branch="$(git config --global --get init.defaultBranch || true)"
  is_blank "${default_branch}"
}

# =============================================================================
# Section: Install flow
# =============================================================================

section "Installing Git"
if command_exists git; then
  log "Git is already installed: $(git --version)"
else
  sudo apt-get install -y git
fi

section "Configuring Git identity"
git_identity_configured=0
git_default_branch_configured=0

if _git_user_identity_needs_configuration; then
  _ensure_private_git_config
  _ensure_git_identity_values
  _set_git_global_if_missing "user.name" "${GIT_USER_NAME}"
  _set_git_global_if_missing "user.email" "${GIT_USER_EMAIL}"
  git_identity_configured=1
else
  log "Global Git user identity is already configured"
fi

if _git_default_branch_needs_configuration; then
  _set_git_global_if_missing "init.defaultBranch" "${GIT_DEFAULT_BRANCH}"
  git_default_branch_configured=1
else
  log "Global Git default branch is already configured"
fi

log "Installed Git version: $(git --version)"
if [ "${git_identity_configured}" -eq 1 ]; then
  log "Configured global Git user identity from ${PRIVATE_GIT_CONFIG}"
fi
if [ "${git_default_branch_configured}" -eq 1 ]; then
  log "Configured Git init.defaultBranch: $(git config --global init.defaultBranch)"
fi

success "Git installation and configuration complete"
