#!/usr/bin/env bash

# =============================================================================
# README - CUDA toolkit installer for Ubuntu on WSL
# =============================================================================
#
# Purpose
# -------
# Install the NVIDIA CUDA toolkit inside Ubuntu running on WSL.
#
# What it does
# ------------
# - checks the installed CUDA release, if any
# - configures NVIDIA's WSL CUDA repository
# - installs the requested CUDA toolkit version or the latest available one
# - caches the CUDA keyring package in `wsl_ubuntu/zfiles`
# - configures Bash PATH for CUDA in a managed `~/.bashrc` block
#
# Notes
# -----
# - This script is intended for Ubuntu on WSL, not a standard Linux desktop.
# - It does not install an NVIDIA Linux driver inside WSL.
# - Run with an optional version like `bash install/cuda_wsl.sh 12.8`.
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

readonly ZFILES_DIR="${REPO_ROOT}/zfiles"
: "${CUDA_SYMLINK_DIR:=/usr/local/cuda}"
: "${CUDA_BIN_DIR:=${CUDA_SYMLINK_DIR}/bin}"
: "${CUDA_BASHRC_PATH:=${HOME}/.bashrc}"
: "${CUDA_PATH_BLOCK_BEGIN:=# >>> WSL Ubuntu CUDA PATH >>>}"
: "${CUDA_PATH_BLOCK_END:=# <<< WSL Ubuntu CUDA PATH <<<}"
: "${CUDA_REPO_URL:=https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64}"
: "${CUDA_KEYRING_PACKAGE:=cuda-keyring_1.1-1_all.deb}"
: "${CUDA_KEYRING_URL:=${CUDA_REPO_URL}/${CUDA_KEYRING_PACKAGE}}"
: "${CUDA_KEYRING_PATH:=${ZFILES_DIR}/${CUDA_KEYRING_PACKAGE}}"

readonly CUDA_REPO_PREREQUISITES=(
  wget
  ca-certificates
)

readonly CUDA_BUILD_REQUIREMENTS=(
  gcc
)

SYSTEM_MAINTENANCE_COMPLETED=0
PACKAGE_METADATA_REFRESHED=0
ACTION_RESULT="unchanged"

# =============================================================================
# Section: Validation helpers
# =============================================================================

# Normalize a user-supplied CUDA version into the apt package suffix format.
normalize_version() {
  local raw="${1:-}"
  local cleaned major minor patch

  cleaned="${raw//_/.}"
  cleaned="${cleaned//-/.}"
  IFS='.' read -r major minor patch _ <<< "${cleaned}"

  if [[ -z "${major}" || -z "${minor}" || ! "${major}" =~ ^[0-9]+$ || ! "${minor}" =~ ^[0-9]+$ ]]; then
    die "Invalid CUDA version '${raw}'. Use major.minor, for example: 12.8"
  fi

  if [[ -n "${patch:-}" ]]; then
    warn "Ignoring patch component '${raw}'; apt packages are selected by major.minor."
  fi

  printf '%s-%s\n' "${major}" "${minor}"
}

# Check whether a Debian package is currently installed.
package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

# =============================================================================
# Section: Query helpers
# =============================================================================

# Resolve the CUDA apt package name for either the latest or a requested version.
resolve_cuda_package() {
  if [[ $# -ge 1 && -n "${1}" && "${1}" != "latest" ]]; then
    printf 'cuda-toolkit-%s\n' "$(normalize_version "${1}")"
    return 0
  fi

  printf 'cuda-toolkit\n'
}

# Reduce a full package version string to a major.minor release.
extract_release_from_version() {
  local version="${1:-}"

  sed -E 's/^([0-9]+)\.([0-9]+).*/\1.\2/' <<< "${version}"
}

# Read the current apt candidate version for a CUDA package.
get_package_candidate_version() {
  local cuda_package="${1}"

  apt-cache policy "${cuda_package}" | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p'
}

# Detect the installed CUDA release from nvcc or installed toolkit packages.
get_installed_cuda_release() {
  local installed_release=""
  local installed_package=""

  if command_exists nvcc; then
    installed_release="$(nvcc --version | sed -n 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/p')"
  fi

  if [[ -n "${installed_release}" ]]; then
    printf '%s\n' "${installed_release}"
    return 0
  fi

  installed_package="$(
    dpkg-query -W -f='${Package}\n' 2>/dev/null \
      | awk '/^cuda-toolkit-[0-9]+-[0-9]+$/ {print $1}' \
      | sort -V \
      | tail -n 1
  )"

  if [[ -n "${installed_package}" ]]; then
    printf '%s\n' "${installed_package#cuda-toolkit-}" | tr '-' '.'
  fi
}

# Print a compact summary of the currently installed CUDA release.
report_installed_cuda_status() {
  local installed_release="${1:-}"

  section "Installed CUDA Status"
  if [[ -n "${installed_release}" ]]; then
    log "Installed CUDA release: ${installed_release}"
  else
    log "Installed CUDA release: none detected"
  fi
}

# Ask whether an installed CUDA release should be updated to a newer one.
confirm_update() {
  local installed_release="${1}"
  local target_release="${2}"

  if ! is_interactive_terminal; then
    warn "CUDA ${installed_release} is installed and ${target_release} is available, but the terminal is non-interactive. Skipping the update."
    return 1
  fi

  prompt_yes_no "CUDA ${installed_release} is installed. Latest available is ${target_release}. Update now?" "no"
}

# =============================================================================
# Section: Download helpers
# =============================================================================

# Validate that a cached CUDA keyring package exists and is a readable .deb file.
is_cached_keyring_usable() {
  local package_path="${1}"

  [ -s "${package_path}" ] || return 1
  dpkg-deb -I "${package_path}" >/dev/null 2>&1
}

# Check whether a PATH-like string already contains a specific directory entry.
path_contains_entry() {
  local path_value="${1}"
  local path_entry="${2}"

  case ":${path_value}:" in
    *":${path_entry}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve the trusted CUDA bin directory that should be added to PATH.
resolve_cuda_bin_dir() {
  if [ -x "${CUDA_BIN_DIR}/nvcc" ]; then
    printf '%s\n' "${CUDA_BIN_DIR}"
    return 0
  fi

  if command_exists nvcc; then
    local nvcc_path=""
    nvcc_path="$(command -v nvcc)"
    case "${nvcc_path}" in
      /usr/local/cuda/bin/nvcc|/usr/local/cuda-*/bin/nvcc)
        dirname "${nvcc_path}"
        return 0
        ;;
    esac
  fi

  return 1
}

# =============================================================================
# Section: Setup helpers
# =============================================================================

# Run the full system maintenance flow once before major package installation.
ensure_system_maintenance() {
  if [[ "${SYSTEM_MAINTENANCE_COMPLETED}" -eq 1 ]]; then
    return 0
  fi

  if [[ "${PACKAGE_METADATA_REFRESHED}" -eq 0 ]]; then
    section "Updating Ubuntu"
    update_system_packages
    PACKAGE_METADATA_REFRESHED=1
  else
    section "Upgrading Ubuntu"
  fi

  upgrade_system_packages
  SYSTEM_MAINTENANCE_COMPLETED=1
}

# Refresh apt package metadata once before any package installation steps.
ensure_package_metadata_refreshed() {
  if [[ "${PACKAGE_METADATA_REFRESHED}" -eq 1 ]]; then
    return 0
  fi

  update_system_packages
  PACKAGE_METADATA_REFRESHED=1
}

# Install only the missing prerequisites required to configure the CUDA repo.
install_repo_prerequisites() {
  local missing_packages=()
  local package=""

  for package in "${CUDA_REPO_PREREQUISITES[@]}"; do
    if ! package_installed "${package}"; then
      missing_packages+=("${package}")
    fi
  done

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    log "CUDA repository prerequisites are already installed"
    return 0
  fi

  section "Installing CUDA Repository Prerequisites"
  sudo apt-get install -y "${missing_packages[@]}"
}

# Install only the missing compiler/build packages required by CUDA tooling.
install_build_requirements() {
  local missing_packages=()
  local package=""

  for package in "${CUDA_BUILD_REQUIREMENTS[@]}"; do
    if ! package_installed "${package}"; then
      missing_packages+=("${package}")
    fi
  done

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    log "CUDA build requirements are already installed"
    return 0
  fi

  section "Installing CUDA Build Requirements"
  sudo apt-get install -y "${missing_packages[@]}"
}

# Install the NVIDIA CUDA apt repository keyring and refresh apt metadata.
install_cuda_repository() {
  local keyring_path=""

  section "Configuring NVIDIA CUDA Repository"
  ensure_directory "${ZFILES_DIR}"

  if is_cached_keyring_usable "${CUDA_KEYRING_PATH}"; then
    log "Using cached CUDA keyring package from ${ZFILES_DIR}"
  else
    log "Downloading CUDA keyring package to ${ZFILES_DIR}"
  fi

  keyring_path="$(download_with_cache "${CUDA_KEYRING_PATH}" "${CUDA_KEYRING_URL}" "is_cached_keyring_usable")"

  log "Installing CUDA keyring package"
  sudo dpkg -i "${keyring_path}" >/dev/null

  log "Refreshing apt metadata after CUDA repository setup"
  sudo apt-get update
}

# Install the requested CUDA toolkit package through apt.
install_cuda_toolkit() {
  local cuda_package="${1}"

  section "Installing CUDA Toolkit"
  log "Installing ${cuda_package}"
  sudo apt-get install -y "${cuda_package}"
}

# Export CUDA into the current PATH and persist one managed PATH block in ~/.bashrc.
configure_cuda_shell_path() {
  local cuda_bin_dir=""
  local temp_file=""

  if ! cuda_bin_dir="$(resolve_cuda_bin_dir)"; then
    if command_exists nvcc; then
      warn "nvcc is available at $(command -v nvcc), but it is not in a managed CUDA install location. Skipping PATH configuration."
    else
      warn "CUDA binary directory could not be resolved. Skipping PATH configuration."
    fi
    return 0
  fi

  section "Configuring CUDA PATH"

  if ! path_contains_entry "${PATH}" "${cuda_bin_dir}"; then
    export PATH="${cuda_bin_dir}:${PATH}"
    log "Added ${cuda_bin_dir} to the current PATH"
  else
    log "CUDA binary directory is already in the current PATH"
  fi

  touch "${CUDA_BASHRC_PATH}"
  temp_file="$(mktemp)"

  awk \
    -v block_begin="${CUDA_PATH_BLOCK_BEGIN}" \
    -v block_end="${CUDA_PATH_BLOCK_END}" '
      $0 == block_begin { in_block=1; next }
      $0 == block_end { in_block=0; next }
      !in_block { print }
    ' "${CUDA_BASHRC_PATH}" > "${temp_file}"

  {
    cat "${temp_file}"
    printf '\n%s\n' "${CUDA_PATH_BLOCK_BEGIN}"
    printf 'if [ -d "%s" ] && [[ ":$PATH:" != *":%s:"* ]]; then\n' "${cuda_bin_dir}" "${cuda_bin_dir}"
    printf '  export PATH="%s:$PATH"\n' "${cuda_bin_dir}"
    printf 'fi\n'
    printf '%s\n' "${CUDA_PATH_BLOCK_END}"
  } > "${CUDA_BASHRC_PATH}"

  rm -f "${temp_file}"
  success "Managed CUDA PATH block written to ${CUDA_BASHRC_PATH}"
}

# =============================================================================
# Section: Decision flow
# =============================================================================

# Decide whether CUDA should be installed, updated, or left unchanged.
check_cuda_status() {
  local cuda_package="${1}"
  local requested_release="${2:-}"
  local installed_release="${3:-}"
  local candidate_version=""
  local candidate_release=""

  candidate_version="$(get_package_candidate_version "${cuda_package}")"
  if [[ -z "${candidate_version}" || "${candidate_version}" == "(none)" ]]; then
    die "Unable to determine an install candidate for ${cuda_package}."
  fi

  candidate_release="$(extract_release_from_version "${candidate_version}")"

  section "CUDA Version Check"
  if [[ -n "${requested_release}" ]]; then
    log "Requested CUDA release: ${requested_release}"
  else
    log "Latest available CUDA release: ${candidate_release}"
  fi

  if [[ -z "${installed_release}" ]]; then
    log "CUDA is not installed. Proceeding with installation."
    ACTION_RESULT="installed"
    return 0
  fi

  if [[ "${installed_release}" == "${candidate_release}" ]]; then
    log "CUDA ${installed_release} is already installed. No action needed."
    ACTION_RESULT="unchanged"
    return 1
  fi

  if [[ -n "${requested_release}" ]]; then
    log "CUDA ${installed_release} is installed. Proceeding to install requested release ${requested_release}."
    ACTION_RESULT="updated"
    return 0
  fi

  if confirm_update "${installed_release}" "${candidate_release}"; then
    ACTION_RESULT="updated"
    return 0
  fi

  ACTION_RESULT="skipped"
  return 1
}

# =============================================================================
# Section: Verification
# =============================================================================

# Print the main CUDA tool versions and installed CUDA-related packages.
print_cuda_tool_info() {
  section "CUDA Tool Information"

  if command_exists nvcc; then
    nvcc --version
  else
    warn "nvcc is not available on PATH."
  fi

  if command_exists nvidia-smi; then
    nvidia-smi || warn "nvidia-smi is present but failed to run."
  else
    warn "nvidia-smi is not available in this WSL environment."
  fi

  dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null \
    | awk '/^cuda-toolkit($|-)/ {print}'
}

# Perform lightweight post-install checks for nvcc and GPU visibility.
verify_cuda_installation() {
  section "Verification"

  if command_exists nvcc && nvcc --version >/dev/null 2>&1; then
    success "CUDA compiler check passed."
  else
    warn "CUDA compiler check failed."
  fi

  if command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    success "GPU visibility check passed."
  else
    warn "GPU visibility check failed or is unavailable."
  fi
}

# Print the final high-level outcome of the CUDA workflow.
print_final_status() {
  section "Final Status"

  case "${ACTION_RESULT}" in
    installed)
      success "CUDA was installed."
      ;;
    updated)
      success "CUDA was updated."
      ;;
    skipped)
      warn "CUDA update was skipped."
      ;;
    unchanged)
      success "CUDA was already current. No changes were required."
      ;;
    *)
      warn "CUDA completed with status: ${ACTION_RESULT}"
      ;;
  esac
}

# =============================================================================
# Section: Main
# =============================================================================

# Execute the full CUDA install/update workflow.
main() {
  local cuda_package=""
  local requested_release=""
  local installed_release=""
  local status=0

  validate_wsl || die "This script is intended for Ubuntu on WSL."
  cuda_package="$(resolve_cuda_package "${1:-}")"
  installed_release="$(get_installed_cuda_release)"
  report_installed_cuda_status "${installed_release}"

  if [[ "${cuda_package}" != "cuda-toolkit" ]]; then
    requested_release="${cuda_package#cuda-toolkit-}"
    requested_release="${requested_release//-/.}"
  fi

  ensure_package_metadata_refreshed
  install_repo_prerequisites
  install_cuda_repository

  if check_cuda_status "${cuda_package}" "${requested_release}" "${installed_release}"; then
    status=0
  else
    status=$?
  fi

  if [[ "${status}" -eq 1 ]]; then
    configure_cuda_shell_path
    print_cuda_tool_info
    verify_cuda_installation
    print_final_status
    return 0
  fi

  ensure_system_maintenance
  install_repo_prerequisites
  install_build_requirements
  install_cuda_toolkit "${cuda_package}"
  configure_cuda_shell_path
  print_cuda_tool_info
  verify_cuda_installation
  print_final_status
}

main "$@"
