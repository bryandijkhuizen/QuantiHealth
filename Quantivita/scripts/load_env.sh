#!/usr/bin/env bash

load_quantivita_env() {
  local root_dir="${1:-$(pwd)}"
  local env_file="${QUANTIVITA_ENV_FILE:-${root_dir}/.env}"

  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}
