#!/usr/bin/env bash

# =============================================================================
# README - Ollama installer and model bootstrap for WSL Ubuntu
# =============================================================================
#
# Purpose
# -------
# Install or update Ollama, make sure the local Ollama server is available, and
# pull the default model set used in this repository.
#
# What it does
# ------------
# - caches the Ollama installer in `wsl_ubuntu/zfiles`
# - verifies the required shell commands and Ubuntu packages only when needed
# - runs Ollama's official Linux installer only when Ollama is missing or the
#   requested version is different
# - enables the Ollama service when systemd is available
# - starts Ollama temporarily when no service is available
# - pulls each configured model with `ollama pull` only when it is missing
# - verifies the CLI and the local service state at the end
#
# Useful environment variables
# ----------------------------
# - `OLLAMA_VERSION=...` installs a specific Ollama version
# - `OLLAMA_SKIP_INSTALL=1` skips the install/update phase
# - `OLLAMA_SKIP_MODELS=1` skips the model pull phase
#
# Notes
# -----
# - This script uses `ollama pull`, not `ollama run`, so it never opens an
#   interactive chat session while installing models.
# - Ollama already uses llama.cpp internally, so a separate llama.cpp install is
#   not required for the normal Ollama workflow.
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/system.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/tooling.sh"

# =============================================================================
# Section: Configuration defaults
# =============================================================================

: "${ZFILES_DIR:=${REPO_ROOT}/zfiles}"
: "${OLLAMA_INSTALL_SCRIPT_URL:=https://ollama.com/install.sh}"
: "${OLLAMA_INSTALL_SCRIPT_NAME:=ollama-install.sh}"
: "${OLLAMA_SERVICE_NAME:=ollama}"
: "${OLLAMA_HOST:=127.0.0.1:11434}"
: "${OLLAMA_SKIP_INSTALL:=0}"
: "${OLLAMA_SKIP_MODELS:=0}"

readonly ZFILES_DIR
readonly OLLAMA_INSTALL_SCRIPT_URL
readonly OLLAMA_INSTALL_SCRIPT_NAME
readonly OLLAMA_SERVICE_NAME
readonly OLLAMA_HOST
readonly OLLAMA_SKIP_INSTALL
readonly OLLAMA_SKIP_MODELS
readonly OLLAMA_INSTALL_SCRIPT_PATH="${ZFILES_DIR}/${OLLAMA_INSTALL_SCRIPT_NAME}"
readonly OLLAMA_TEMP_LOG_FILE="/tmp/ollama-model-install.log"

readonly OLLAMA_PREREQUISITES=(
  ca-certificates
  curl
  zstd
)

readonly OLLAMA_INSTALLER_COMMANDS=(
  awk
  curl
  grep
  sed
  tee
  xargs
  zstd
)

readonly OLLAMA_MODEL_NAMES=(
  qwen3.6:27b
  qwen3.6:35b
  nemotron3:33b
  granite4.1:3b
  granite4.1:8b
  granite4.1:30b
  gemma4:e2b
  gemma4:e4b
  gemma4:26b
  gemma4:31b
)

TEMP_OLLAMA_PID=""

INSTALL_ACTION="skipped"
MODEL_ACTION="skipped"

# =============================================================================
# Section: Environment checks
# =============================================================================

has_systemd() {
  [ "$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ')" = "systemd" ]
}

ollama_service_exists() {
  has_systemd && systemctl cat "${OLLAMA_SERVICE_NAME}.service" >/dev/null 2>&1
}

get_installed_ollama_version() {
  local version_output=""

  if ! command_exists ollama; then
    return 1
  fi

  version_output="$(ollama --version 2>/dev/null || true)"
  sed -n 's/.*\([0-9][0-9.]*\).*/\1/p' <<< "${version_output}" | head -n 1
}

# =============================================================================
# Section: Cleanup
# =============================================================================

cleanup_temporary_ollama_server() {
  if [ -n "${TEMP_OLLAMA_PID}" ] && kill -0 "${TEMP_OLLAMA_PID}" >/dev/null 2>&1; then
    log "Stopping temporary Ollama server."
    kill "${TEMP_OLLAMA_PID}" >/dev/null 2>&1 || true
  fi
}

# =============================================================================
# Section: Install phase
# =============================================================================

is_cached_ollama_installer_usable() {
  local script_path="${1}"

  [ -s "${script_path}" ] || return 1
  grep -q "ollama" "${script_path}"
}

install_prerequisites() {
  local missing_packages=()
  local package_name=""

  for package_name in "${OLLAMA_PREREQUISITES[@]}"; do
    if ! package_installed "${package_name}"; then
      missing_packages+=("${package_name}")
    fi
  done

  if [ "${#missing_packages[@]}" -eq 0 ]; then
    log "Ollama install prerequisites are already installed."
    return 0
  fi

  section "Installing Ollama Prerequisites"
  update_system_packages
  sudo DEBIAN_FRONTEND=noninteractive apt-get \
    -o Acquire::Retries="${APT_RETRY_COUNT}" \
    -o DPkg::Lock::Timeout="${APT_LOCK_TIMEOUT}" \
    install -y "${missing_packages[@]}"
}

require_ollama_installer_commands() {
  local command_name=""

  for command_name in "${OLLAMA_INSTALLER_COMMANDS[@]}"; do
    require_command "${command_name}"
  done
}

download_ollama_installer() {
  if is_cached_ollama_installer_usable "${OLLAMA_INSTALL_SCRIPT_PATH}"; then
    log "Using cached Ollama installer from ${ZFILES_DIR}"
  else
    log "Downloading Ollama installer to ${OLLAMA_INSTALL_SCRIPT_PATH}"
  fi

  download_with_cache \
    "${OLLAMA_INSTALL_SCRIPT_PATH}" \
    "${OLLAMA_INSTALL_SCRIPT_URL}" \
    "is_cached_ollama_installer_usable" >/dev/null
}

should_run_ollama_installer() {
  local installed_version=""

  if ! command_exists ollama; then
    return 0
  fi

  if [ -n "${OLLAMA_VERSION:-}" ]; then
    installed_version="$(get_installed_ollama_version)"
    if [ "${installed_version}" != "${OLLAMA_VERSION}" ]; then
      log "Installed Ollama version is ${installed_version:-unknown}; requested version is ${OLLAMA_VERSION}."
      return 0
    fi

    log "Ollama ${OLLAMA_VERSION} is already installed."
    return 1
  fi

  log "Ollama is already installed. Skipping reinstall."
  return 1
}

run_ollama_installer() {
  section "Installing Ollama"

  if ! should_run_ollama_installer; then
    INSTALL_ACTION="skipped"
    return 0
  fi

  download_ollama_installer

  if [ -n "${OLLAMA_VERSION:-}" ]; then
    log "Requested Ollama version: ${OLLAMA_VERSION}"
    OLLAMA_VERSION="${OLLAMA_VERSION}" sh "${OLLAMA_INSTALL_SCRIPT_PATH}"
  else
    sh "${OLLAMA_INSTALL_SCRIPT_PATH}"
  fi

  INSTALL_ACTION="installed"
}

configure_ollama_service() {
  section "Configuring Ollama Service"

  if ! has_systemd; then
    warn "systemd is not active in this WSL distro."
    warn "Ollama can still run in the foreground with: ollama serve"
    return 0
  fi

  if sudo systemctl is-active --quiet "${OLLAMA_SERVICE_NAME}"; then
    success "${OLLAMA_SERVICE_NAME}.service is already active."
    return 0
  fi

  log "Enabling and starting ${OLLAMA_SERVICE_NAME}.service"
  if sudo systemctl enable --now "${OLLAMA_SERVICE_NAME}"; then
    success "${OLLAMA_SERVICE_NAME}.service is enabled and started."
    return 0
  fi

  warn "Unable to enable or start ${OLLAMA_SERVICE_NAME}.service."
  warn "Review the service with: sudo systemctl status ${OLLAMA_SERVICE_NAME}"
}

run_install_phase() {
  local installer_needed=1

  if [ "${OLLAMA_SKIP_INSTALL}" = "1" ]; then
    log "Skipping Ollama install/update phase because OLLAMA_SKIP_INSTALL=1."
    INSTALL_ACTION="skipped"
    return 0
  fi

  if should_run_ollama_installer; then
    installer_needed=0
    require_command sudo
    sudo -v
    install_prerequisites
    require_ollama_installer_commands
    run_ollama_installer
  fi

  if [ "${installer_needed}" -ne 0 ]; then
    INSTALL_ACTION="skipped"
  fi

  configure_ollama_service
}

# =============================================================================
# Section: Model phase
# =============================================================================

configure_ollama_client() {
  export OLLAMA_HOST
  log "Using Ollama host: ${OLLAMA_HOST}"
  log "Using Ollama's default model storage location."
}

wait_for_ollama_server() {
  local attempt=0

  for attempt in {1..30}; do
    if ollama list >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  die "Ollama did not become ready. Check ${OLLAMA_TEMP_LOG_FILE} or the Ollama service logs."
}

ensure_ollama_server() {
  section "Checking Ollama Server"

  if ollama list >/dev/null 2>&1; then
    success "Ollama is responding."
    return 0
  fi

  if ollama_service_exists; then
    require_command sudo
    sudo -v

    log "Starting ${OLLAMA_SERVICE_NAME}.service."
    sudo systemctl enable --now "${OLLAMA_SERVICE_NAME}"
    wait_for_ollama_server
    success "Ollama is responding."
    return 0
  fi

  log "Starting a temporary Ollama server for model pulls."
  ollama serve >"${OLLAMA_TEMP_LOG_FILE}" 2>&1 &
  TEMP_OLLAMA_PID="$!"
  wait_for_ollama_server
  success "Temporary Ollama server is responding."
}

model_is_installed() {
  local model_name="${1}"

  ollama show "${model_name}" >/dev/null 2>&1
}

install_models() {
  local model_name=""
  local installed_any_model=1

  section "Installing Ollama Models"

  for model_name in "${OLLAMA_MODEL_NAMES[@]}"; do
    if model_is_installed "${model_name}"; then
      log "Model already installed: ${model_name}"
      continue
    fi

    log "Installing ${model_name}..."
    ollama pull "${model_name}"
    installed_any_model=0
  done

  if [ "${installed_any_model}" -eq 0 ]; then
    MODEL_ACTION="installed"
  else
    MODEL_ACTION="skipped"
    log "All configured Ollama models are already installed."
  fi

  success "Ollama model installation complete."
}

run_model_phase() {
  if [ "${OLLAMA_SKIP_MODELS}" = "1" ]; then
    log "Skipping model installation because OLLAMA_SKIP_MODELS=1."
    MODEL_ACTION="skipped"
    return 0
  fi

  require_command ollama
  configure_ollama_client
  ensure_ollama_server
  install_models
}

# =============================================================================
# Section: Verification and summary
# =============================================================================

print_llama_cpp_note() {
  section "llama.cpp Note"
  log "Skipping separate llama.cpp installation. It is not required for a normal Ollama install."
  log "Install llama.cpp later only for direct llama.cpp workflows or model conversion tools."
}

verify_ollama_cli() {
  section "Ollama CLI Check"

  if ! command_exists ollama; then
    die "Ollama command was not found after installation."
  fi

  ollama --version
  success "Ollama CLI is available."
}

verify_ollama_service() {
  section "Ollama Service Check"

  if has_systemd; then
    if sudo systemctl is-active --quiet "${OLLAMA_SERVICE_NAME}"; then
      success "${OLLAMA_SERVICE_NAME}.service is active."
    else
      warn "${OLLAMA_SERVICE_NAME}.service is not active."
    fi
    return 0
  fi

  if pgrep -x ollama >/dev/null 2>&1; then
    success "An Ollama process is running."
  else
    warn "No Ollama service/process is running. Use 'ollama serve' before calling the API."
  fi
}

print_summary() {
  section "Summary"

  echo "Ollama host:   ${OLLAMA_HOST}"
  echo "Model folder:  Ollama default"
  echo "Model count:   ${#OLLAMA_MODEL_NAMES[@]}"
  echo "Skip install:  ${OLLAMA_SKIP_INSTALL}"
  echo "Skip models:   ${OLLAMA_SKIP_MODELS}"
  echo "Install step:  ${INSTALL_ACTION}"
  echo "Model step:    ${MODEL_ACTION}"
}

# =============================================================================
# Section: Main entrypoint
# =============================================================================

main() {
  trap cleanup_temporary_ollama_server EXIT

  log "Starting Ollama setup for WSL Ubuntu..."

  run_install_phase
  run_model_phase
  print_llama_cpp_note
  verify_ollama_cli
  verify_ollama_service
  print_summary

  success "Ollama setup flow complete."
}

main "$@"
