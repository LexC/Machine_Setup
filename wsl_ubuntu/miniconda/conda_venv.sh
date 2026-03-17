#!/usr/bin/env bash

# =============================================================================
# README - Conda environment manager for WSL Ubuntu
# =============================================================================
#
# Purpose
# -------
# Create, list, and delete Conda environments managed by the local Miniconda
# installation, with optional toolchains installed during environment creation.
#
# What it does
# ------------
# - supports `create`, `delete`, and `list` environment actions
# - optionally installs Python, Java, C++, R, Go, Rust, Julia, PowerShell,
#   Octave, and Groovy into a new environment
# - prompts interactively for missing action, environment, and package version
#   values when the command line does not fully specify them
#
# Notes
# -----
# - This script expects Miniconda to already be installed.
# - Package flags are only supported with the `create` action.
# - Re-running `create` with `--force` recreates the environment from scratch.
#
# =============================================================================

# =============================================================================
# Section: Script bootstrap
# =============================================================================

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  "${BASH:-bash}" "${BASH_SOURCE[0]}" "$@"
  return $?
fi

set -euo pipefail

# =============================================================================
# Section: Dependencies
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${REPO_ROOT}/utils/tooling.sh"

# =============================================================================
# Section: Configuration defaults
# =============================================================================

: "${MINICONDA_INSTALL_DIR:=${HOME}/miniconda3}"

readonly PACKAGE_TABLE=(
  "python|Python|-python|defaults|python|python --version|versioned"
  "java|Java|-java|conda-forge|openjdk|java -version|versioned"
  "cpp|C++|-cpp|conda-forge|gxx_linux-64 cmake make ninja boost|g++ --version|versioned"
  "r|R|-r|conda-forge|r-base|R --version|versioned"
  "go|Go|-go|conda-forge|go|go version|versioned"
  "rust|Rust|-rust|conda-forge|rust|rustc --version|versioned"
  "julia|Julia|-julia|conda-forge|julia|julia --version|versioned"
  "powershell|PowerShell|-powershell|conda-forge|powershell|pwsh --version|versioned"
  "octave|Octave|-octave|conda-forge|octave|octave --version|versioned"
  "groovy|Groovy|-groovy|conda-forge|groovy|groovy --version|versioned"
)

ACTION=""
ENV_NAME=""
FORCE_RECREATE=0
ASSUME_YES=0
CONDA_CMD=""
PACKAGE_REGISTRY_READY=0
ENV_CACHE_READY=0

declare -a PACKAGE_IDS=()
declare -A PACKAGE_DISPLAY_NAME=()
declare -A PACKAGE_FLAG=()
declare -A PACKAGE_CHANNEL=()
declare -A PACKAGE_SPECS=()
declare -A PACKAGE_VERIFY_COMMAND=()
declare -A PACKAGE_MODE=()
declare -A PACKAGE_ID_BY_FLAG=()
declare -A PACKAGE_ID_BY_MENU_INDEX=()
declare -A SELECTED_PACKAGES=()
declare -A PACKAGE_VERSION_OVERRIDES=()
declare -A KNOWN_ENVIRONMENTS=()

# =============================================================================
# Section: Package registry helpers
# =============================================================================

init_package_registry() {
  local package_row=""
  local package_id=""
  local display_name=""
  local cli_flag=""
  local channel=""
  local package_specs=""
  local verify_command=""
  local mode=""
  local menu_index=1

  if [ "${PACKAGE_REGISTRY_READY}" -eq 1 ]; then
    return 0
  fi

  PACKAGE_IDS=()
  PACKAGE_DISPLAY_NAME=()
  PACKAGE_FLAG=()
  PACKAGE_CHANNEL=()
  PACKAGE_SPECS=()
  PACKAGE_VERIFY_COMMAND=()
  PACKAGE_MODE=()
  PACKAGE_ID_BY_FLAG=()
  PACKAGE_ID_BY_MENU_INDEX=()

  for package_row in "${PACKAGE_TABLE[@]}"; do
    IFS='|' read -r package_id display_name cli_flag channel package_specs verify_command mode <<< "${package_row}"
    PACKAGE_IDS+=("${package_id}")
    PACKAGE_DISPLAY_NAME["${package_id}"]="${display_name}"
    PACKAGE_FLAG["${package_id}"]="${cli_flag}"
    PACKAGE_CHANNEL["${package_id}"]="${channel}"
    PACKAGE_SPECS["${package_id}"]="${package_specs}"
    PACKAGE_VERIFY_COMMAND["${package_id}"]="${verify_command}"
    PACKAGE_MODE["${package_id}"]="${mode}"
    PACKAGE_ID_BY_FLAG["${cli_flag}"]="${package_id}"
    PACKAGE_ID_BY_MENU_INDEX["${menu_index}"]="${package_id}"
    menu_index=$((menu_index + 1))
  done

  PACKAGE_REGISTRY_READY=1
}

# =============================================================================
# Section: CLI help and package selection helpers
# =============================================================================

print_usage() {
  local usage_fragments=()
  local package_id=""

  for package_id in "${PACKAGE_IDS[@]}"; do
    usage_fragments+=("[${PACKAGE_FLAG["${package_id}"]}]")
  done

  cat <<EOF
Usage:
  conda_venv.sh create --venv <name> [--force] ${usage_fragments[*]}
  conda_venv.sh delete --venv <name> [--yes]
  conda_venv.sh list

Actions:
  create                Create a Conda environment.
  delete                Delete a Conda environment.
  list                  List Conda environments.

Options:
  --venv, --name        Conda environment name.
  --force, -f           Recreate the environment if it already exists.
  --yes, -y             Skip delete confirmation.
EOF

  for package_id in "${PACKAGE_IDS[@]}"; do
    if [ "${PACKAGE_MODE["${package_id}"]}" = "versioned" ]; then
      printf '  %-20s Install %s from %s. Interactive prompt chooses version; blank uses latest.\n' \
        "${PACKAGE_FLAG["${package_id}"]}" \
        "${PACKAGE_DISPLAY_NAME["${package_id}"]}" \
        "${PACKAGE_CHANNEL["${package_id}"]}"
    else
      printf '  %-20s Install %s from %s.\n' \
        "${PACKAGE_FLAG["${package_id}"]}" \
        "${PACKAGE_DISPLAY_NAME["${package_id}"]}" \
        "${PACKAGE_CHANNEL["${package_id}"]}"
    fi
  done

  printf '  %-20s Show this help message.\n' "--help, -h"
}

select_package() {
  local package_id="${1}"
  SELECTED_PACKAGES["${package_id}"]=1
}

package_is_selected() {
  local package_id="${1}"
  [ "${SELECTED_PACKAGES["${package_id}"]:-0}" -eq 1 ]
}

set_package_version_override() {
  local package_id="${1}"
  local version_value="${2}"
  PACKAGE_VERSION_OVERRIDES["${package_id}"]="${version_value}"
}

get_package_version_override() {
  local package_id="${1}"
  printf '%s\n' "${PACKAGE_VERSION_OVERRIDES["${package_id}"]:-}"
}

reset_runtime_state() {
  ACTION=""
  ENV_NAME=""
  FORCE_RECREATE=0
  ASSUME_YES=0
  CONDA_CMD=""
  ENV_CACHE_READY=0
  SELECTED_PACKAGES=()
  PACKAGE_VERSION_OVERRIDES=()
  KNOWN_ENVIRONMENTS=()
}

# =============================================================================
# Section: Interactive package configuration
# =============================================================================

prompt_for_package_configuration() {
  local package_id="${1}"
  local version_value=""

  if [ "${PACKAGE_MODE["${package_id}"]}" != "versioned" ]; then
    return 0
  fi

  read -r -p "${PACKAGE_DISPLAY_NAME["${package_id}"]} version [latest]: " version_value
  set_package_version_override "${package_id}" "${version_value}"
}

prompt_for_selected_package_versions() {
  local package_id=""

  require_interactive_terminal

  for package_id in "${PACKAGE_IDS[@]}"; do
    if ! package_is_selected "${package_id}"; then
      continue
    fi

    prompt_for_package_configuration "${package_id}"
  done
}

# =============================================================================
# Section: Environment cache helpers
# =============================================================================

refresh_environment_cache() {
  local env_name=""
  local env_list_output=""

  if ! env_list_output="$("${CONDA_CMD}" env list)"; then
    die "Failed to list Conda environments using ${CONDA_CMD}"
  fi

  KNOWN_ENVIRONMENTS=()
  while IFS= read -r env_name; do
    if [ -n "${env_name}" ]; then
      KNOWN_ENVIRONMENTS["${env_name}"]=1
    fi
  done < <(printf '%s\n' "${env_list_output}" | awk '/^[^#[:space:]]/ {print $1}')

  ENV_CACHE_READY=1
}

invalidate_environment_cache() {
  ENV_CACHE_READY=0
  KNOWN_ENVIRONMENTS=()
}

environment_exists() {
  local env_name="${1}"

  if [ "${ENV_CACHE_READY}" -ne 1 ]; then
    refresh_environment_cache
  fi

  [ "${KNOWN_ENVIRONMENTS["${env_name}"]:-0}" -eq 1 ]
}

# =============================================================================
# Section: Interactive workflow helpers
# =============================================================================

prompt_for_action() {
  local answer=""

  require_interactive_terminal

  section "Select action"
  printf '\nChoose what you want this script to do with your Conda environments.\n'
  printf '\t1. create - create a new Conda environment and optionally install tools\n'
  printf '\t2. delete - remove an existing Conda environment after confirmation\n'
  printf '\t3. list   - show the Conda environments currently available on this machine\n\n'

  while true; do
    read -r -p "Choose an action [1-3]: " answer
    case "${answer}" in
      1|create)
        ACTION="create"
        return 0
        ;;
      2|delete)
        ACTION="delete"
        return 0
        ;;
      3|list)
        ACTION="list"
        return 0
        ;;
      *)
        warn "Please choose create, delete, or list."
        ;;
    esac
  done
}

prompt_for_env_name() {
  local prompt_label="${1}"

  prompt_required_value "${prompt_label}" ENV_NAME "Environment name cannot be empty."
}

prompt_for_optional_packages() {
  local selections=""
  local selected_item=""
  local package_id=""
  local item_number=1

  require_interactive_terminal

  section "Optional packages"
  for package_id in "${PACKAGE_IDS[@]}"; do
    printf '%s. %s\n' "${item_number}" "${PACKAGE_DISPLAY_NAME["${package_id}"]}"
    item_number=$((item_number + 1))
  done

  read -r -p "Select packages to install (for example: 1 3 6), or press Enter to skip: " selections

  for selected_item in ${selections}; do
    package_id="${PACKAGE_ID_BY_MENU_INDEX["${selected_item}"]:-}"
    if [ -z "${package_id}" ]; then
      warn "Ignoring unsupported package selection: ${selected_item}"
      continue
    fi

    select_package "${package_id}"
  done
}

verify_environment_name() {
  if is_blank "${ENV_NAME}"; then
    die "Environment name cannot be empty."
  fi

  if [ "${ENV_NAME}" = "base" ]; then
    die "The base Conda environment is managed separately and cannot be modified here."
  fi
}

# =============================================================================
# Section: Package installation helpers
# =============================================================================

build_package_install_args() {
  local package_specs="${1}"
  local mode="${2}"
  local version_value="${3}"
  local output_array_name="${4}"
  local -n output_array_ref="${output_array_name}"

  output_array_ref=()
  read -r -a output_array_ref <<< "${package_specs}"

  if [ "${mode}" = "versioned" ] && ! is_blank "${version_value}" && [ "${#output_array_ref[@]}" -gt 0 ]; then
    output_array_ref=("${output_array_ref[0]}=${version_value}" "${output_array_ref[@]:1}")
  fi
}

verify_package_install() {
  local package_id="${1}"
  local -a verify_args=()

  log "Verifying ${PACKAGE_DISPLAY_NAME["${package_id}"]} installation"
  read -r -a verify_args <<< "${PACKAGE_VERIFY_COMMAND["${package_id}"]}"
  "${CONDA_CMD}" run -n "${ENV_NAME}" "${verify_args[@]}"
}

install_package_into_environment() {
  local package_id="${1}"
  local version_value=""
  local -a install_packages=()

  version_value="$(get_package_version_override "${package_id}")"
  build_package_install_args \
    "${PACKAGE_SPECS["${package_id}"]}" \
    "${PACKAGE_MODE["${package_id}"]}" \
    "${version_value}" \
    install_packages

  major_section "Installing ${PACKAGE_DISPLAY_NAME["${package_id}"]}"
  if [ "${PACKAGE_MODE["${package_id}"]}" = "versioned" ] && ! is_blank "${version_value}" ; then
    log "Installing ${PACKAGE_DISPLAY_NAME["${package_id}"]} ${version_value} into ${ENV_NAME}"
  else
    log "Installing the latest ${PACKAGE_DISPLAY_NAME["${package_id}"]} into ${ENV_NAME}"
  fi
  "${CONDA_CMD}" install -n "${ENV_NAME}" -c "${PACKAGE_CHANNEL["${package_id}"]}" "${install_packages[@]}" -y
  verify_package_install "${package_id}"
}

install_selected_packages() {
  local package_id=""

  for package_id in "${PACKAGE_IDS[@]}"; do
    if ! package_is_selected "${package_id}" || [ "${package_id}" = "python" ]; then
      continue
    fi

    install_package_into_environment "${package_id}"
  done
}

fail_if_packages_selected_for_non_create() {
  local package_id=""

  for package_id in "${PACKAGE_IDS[@]}"; do
    if package_is_selected "${package_id}"; then
      die "${PACKAGE_FLAG["${package_id}"]} is only supported with the create action."
    fi
  done
}

# =============================================================================
# Section: Argument parsing and validation
# =============================================================================

parse_arguments() {
  local package_id=""

  while [ $# -gt 0 ]; do
    case "${1}" in
      create|delete|list)
        if [ -n "${ACTION}" ]; then
          die "Only one action may be provided."
        fi
        ACTION="${1}"
        ;;
      --venv|--name)
        shift
        require_option_value "--venv" "${1-}"
        ENV_NAME="${1}"
        ;;
      --force|-f)
        FORCE_RECREATE=1
        ;;
      --yes|-y)
        ASSUME_YES=1
        ;;
      --help|-h)
        print_usage
        return 1
        ;;
      *)
        package_id="${PACKAGE_ID_BY_FLAG["${1}"]:-}"
        if [ -z "${package_id}" ]; then
          die "Unsupported argument: ${1}"
        fi
        select_package "${package_id}"
        ;;
    esac

    shift
  done
}

validate_action_specific_arguments() {
  case "${ACTION}" in
    create)
      if [ "${ASSUME_YES}" -eq 1 ]; then
        die "--yes is only supported with the delete action."
      fi
      ;;
    delete)
      if [ "${FORCE_RECREATE}" -eq 1 ]; then
        die "--force is only supported with the create action."
      fi
      fail_if_packages_selected_for_non_create
      ;;
    list)
      if ! is_blank "${ENV_NAME}"; then
        die "--venv/--name is not supported with the list action."
      fi
      if [ "${FORCE_RECREATE}" -eq 1 ]; then
        die "--force is only supported with the create action."
      fi
      if [ "${ASSUME_YES}" -eq 1 ]; then
        die "--yes is only supported with the delete action."
      fi
      fail_if_packages_selected_for_non_create
      ;;
  esac
}

resolve_requested_action() {
  case "${ACTION}" in
    "")
      if is_interactive_terminal; then
        prompt_for_action
      else
        print_usage
        die "An action is required."
      fi
      ;;
    create|delete|list)
      ;;
    *)
      die "Unsupported action: ${ACTION}"
      ;;
  esac
}

# =============================================================================
# Section: Conda command helpers
# =============================================================================

ensure_conda_command() {
  if [ -z "${CONDA_CMD}" ]; then
    CONDA_CMD="$(resolve_conda_command)" || die "Conda was not found on PATH or at ${CONDA_DEFAULT_BIN:-${MINICONDA_INSTALL_DIR}/bin/conda}"
  fi
}

handle_list_action() {
  if [ "${ACTION}" != "list" ]; then
    return 1
  fi

  ensure_conda_command
  section "Available Conda environments"
  "${CONDA_CMD}" env list
  log "Using Conda executable: ${CONDA_CMD}"
  success "Conda environment listing complete"
  return 0
}

prompt_for_missing_env_name() {
  if ! is_blank "${ENV_NAME}"; then
    return 0
  fi

  if ! is_interactive_terminal; then
    die "--venv/--name is required with the ${ACTION} action in non-interactive mode."
  fi

  if [ "${ACTION}" = "delete" ]; then
    ensure_conda_command
    section "Available Conda environments"
    "${CONDA_CMD}" env list
  fi

  prompt_for_env_name "Conda environment name"
}

# =============================================================================
# Section: Environment creation helpers
# =============================================================================

prepare_environment_create() {
  local output_array_name="${1}"
  local python_version_override=""
  local log_message_name="${2}"
  local -n output_array_ref="${output_array_name}"
  local -n log_message_ref="${log_message_name}"
  local -a python_install_packages=()

  output_array_ref=(-n "${ENV_NAME}" -y)
  log_message_ref="Creating environment ${ENV_NAME}"

  if ! package_is_selected "python"; then
    return 0
  fi

  python_version_override="$(get_package_version_override "python")"
  build_package_install_args \
    "${PACKAGE_SPECS["python"]}" \
    "${PACKAGE_MODE["python"]}" \
    "${python_version_override}" \
    python_install_packages

  output_array_ref+=(-c "${PACKAGE_CHANNEL["python"]}" "${python_install_packages[@]}")
  if is_blank "${python_version_override}"; then
    log_message_ref="Creating environment ${ENV_NAME} with the latest Python"
  else
    log_message_ref="Creating environment ${ENV_NAME} with Python ${python_version_override}"
  fi
}

# =============================================================================
# Section: Environment action workflows
# =============================================================================

create_environment() {
  local -a create_args=()
  local create_message=""
  local recreate_existing=0

  section "Creating Conda environment"

  if environment_exists "${ENV_NAME}"; then
    warn "The environment ${ENV_NAME} already exists."

    if [ "${FORCE_RECREATE}" -eq 1 ]; then
      recreate_existing=1
    elif ! is_interactive_terminal; then
      die "Environment ${ENV_NAME} already exists. Re-run with --force to recreate it."
    elif prompt_yes_no "Do you want to recreate ${ENV_NAME}?" "no"; then
      recreate_existing=1
    else
      die "Environment creation cancelled."
    fi

    if [ "${recreate_existing}" -eq 1 ]; then
      log "Removing existing environment ${ENV_NAME} before recreation"
      "${CONDA_CMD}" remove --name "${ENV_NAME}" --all -y
      invalidate_environment_cache
    fi
  fi

  if [ "${#SELECTED_PACKAGES[@]}" -eq 0 ] && is_interactive_terminal; then
    prompt_for_optional_packages
  fi

  if is_interactive_terminal; then
    prompt_for_selected_package_versions
  fi

  prepare_environment_create create_args create_message
  log "${create_message}"
  "${CONDA_CMD}" create "${create_args[@]}"
  invalidate_environment_cache

  if ! environment_exists "${ENV_NAME}"; then
    die "Failed to create Conda environment: ${ENV_NAME}"
  fi

  if package_is_selected "python"; then
    verify_package_install "python"
  fi

  install_selected_packages
  success "Conda environment ${ENV_NAME} is ready"
}

delete_environment() {
  section "Deleting Conda environment"

  if ! environment_exists "${ENV_NAME}"; then
    die "Conda environment does not exist: ${ENV_NAME}"
  fi

  if [ "${ASSUME_YES}" -ne 1 ]; then
    if ! is_interactive_terminal; then
      die "Deletion requires confirmation. Re-run with --yes to delete ${ENV_NAME} non-interactively."
    fi

    prompt_yes_no "Delete Conda environment ${ENV_NAME}?" "no" || {
      log "Deletion cancelled."
      return 0
    }
  fi

  log "Deleting environment ${ENV_NAME}"
  "${CONDA_CMD}" remove --name "${ENV_NAME}" --all -y
  invalidate_environment_cache

  if environment_exists "${ENV_NAME}"; then
    die "Failed to delete Conda environment: ${ENV_NAME}"
  fi

  success "Conda environment ${ENV_NAME} was deleted"
}

run_action_workflow() {
  major_section "Conda environment manager"
  log "Using Conda executable: ${CONDA_CMD}"

  case "${ACTION}" in
    create)
      create_environment
      ;;
    delete)
      delete_environment
      ;;
  esac
}

# =============================================================================
# Section: Entrypoint
# =============================================================================

main() {
  init_package_registry
  reset_runtime_state

  if ! parse_arguments "$@"; then
    return 0
  fi

  resolve_requested_action
  validate_action_specific_arguments

  if handle_list_action; then
    return 0
  fi

  prompt_for_missing_env_name
  verify_environment_name
  ensure_conda_command
  run_action_workflow
}

main "$@"
