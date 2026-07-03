#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUANTIVITA_DIR="${ROOT_DIR}/Quantivita"
PROGRESSA_DIR="${ROOT_DIR}/Progressa/progressa"

QUANTIVITA_API_BASE_URL="${QUANTIVITA_API_BASE_URL:-https://api.quantivita.bryandijkh.com}"
PROGRESSA_AUTH_BASE_URL="${PROGRESSA_AUTH_BASE_URL:-https://api.progressa.bryandijkh.com}"
PROGRESSA_CONNECT_API_BASE_URL="${PROGRESSA_CONNECT_API_BASE_URL:-https://api.progressa.bryandijkh.com}"

BUILD_QUANTIVITA=1
BUILD_PROGRESSA=1
RUN_CLEAN=1
RUN_PUB_GET=1
RUN_ASC_CHECK=1
EXPORT_METHOD="${IOS_EXPORT_METHOD:-app-store}"

QUANTIVITA_VERSION=""
QUANTIVITA_BUILD_NUMBER=""
PROGRESSA_VERSION=""
PROGRESSA_BUILD_NUMBER=""

usage() {
  cat <<'EOF'
Usage: ./build_testflight_ipas.sh [options]

Builds signed TestFlight/App Store IPAs for Quantivita and Progressa.

By default, each app uses the version from pubspec.yaml and build number +1.

Options:
  --only quantivita|progressa   Build only one app
  --quantivita-version VERSION  Override Quantivita version, e.g. 0.0.1
  --quantivita-build NUMBER     Override Quantivita build number
  --progressa-version VERSION   Override Progressa version, e.g. 1.6.3
  --progressa-build NUMBER      Override Progressa build number
  --export-method METHOD        app-store, ad-hoc, development, enterprise
  --no-clean                    Skip flutter clean
  --no-pub-get                  Skip flutter pub get
  --skip-asc-check              Skip Quantivita App Store Connect preflight
  -h, --help                    Show help

Environment defaults:
  QUANTIVITA_API_BASE_URL=https://api.quantivita.bryandijkh.com
  PROGRESSA_AUTH_BASE_URL=https://api.progressa.bryandijkh.com
  PROGRESSA_CONNECT_API_BASE_URL=https://api.progressa.bryandijkh.com

Examples:
  ./build_testflight_ipas.sh
  ./build_testflight_ipas.sh --only progressa --progressa-build 4
  ./build_testflight_ipas.sh --quantivita-build 3 --progressa-build 4
EOF
}

pubspec_version() {
  local pubspec="$1"
  awk -F'[:+ ]+' '/^version:/ { print $2; exit }' "${pubspec}"
}

pubspec_build_number() {
  local pubspec="$1"
  awk -F'[:+ ]+' '/^version:/ { print $3; exit }' "${pubspec}"
}

next_build_number() {
  local current="$1"
  if [[ -z "${current}" ]]; then
    echo "1"
  else
    echo $((current + 1))
  fi
}

require_semver() {
  local label="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${label} must look like x.y.z, got '${value}'." >&2
    exit 2
  fi
}

require_integer() {
  local label="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "${label} must be an integer, got '${value}'." >&2
    exit 2
  fi
}

run_step() {
  echo
  echo "==> $*"
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      case "$2" in
        quantivita)
          BUILD_QUANTIVITA=1
          BUILD_PROGRESSA=0
          ;;
        progressa)
          BUILD_QUANTIVITA=0
          BUILD_PROGRESSA=1
          ;;
        *)
          echo "--only must be quantivita or progressa." >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --quantivita-version)
      QUANTIVITA_VERSION="$2"
      shift 2
      ;;
    --quantivita-build)
      QUANTIVITA_BUILD_NUMBER="$2"
      shift 2
      ;;
    --progressa-version)
      PROGRESSA_VERSION="$2"
      shift 2
      ;;
    --progressa-build)
      PROGRESSA_BUILD_NUMBER="$2"
      shift 2
      ;;
    --export-method)
      EXPORT_METHOD="$2"
      shift 2
      ;;
    --no-clean)
      RUN_CLEAN=0
      shift
      ;;
    --no-pub-get)
      RUN_PUB_GET=0
      shift
      ;;
    --skip-asc-check)
      RUN_ASC_CHECK=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${EXPORT_METHOD}" in
  app-store|ad-hoc|development|enterprise) ;;
  *)
    echo "Invalid --export-method '${EXPORT_METHOD}'." >&2
    exit 2
    ;;
esac

if [[ "${BUILD_QUANTIVITA}" == "1" ]]; then
  QUANTIVITA_VERSION="${QUANTIVITA_VERSION:-$(pubspec_version "${QUANTIVITA_DIR}/pubspec.yaml")}"
  QUANTIVITA_BUILD_NUMBER="${QUANTIVITA_BUILD_NUMBER:-$(next_build_number "$(pubspec_build_number "${QUANTIVITA_DIR}/pubspec.yaml")")}"
  require_semver "--quantivita-version" "${QUANTIVITA_VERSION}"
  require_integer "--quantivita-build" "${QUANTIVITA_BUILD_NUMBER}"
fi

if [[ "${BUILD_PROGRESSA}" == "1" ]]; then
  PROGRESSA_VERSION="${PROGRESSA_VERSION:-$(pubspec_version "${PROGRESSA_DIR}/pubspec.yaml")}"
  PROGRESSA_BUILD_NUMBER="${PROGRESSA_BUILD_NUMBER:-$(next_build_number "$(pubspec_build_number "${PROGRESSA_DIR}/pubspec.yaml")")}"
  require_semver "--progressa-version" "${PROGRESSA_VERSION}"
  require_integer "--progressa-build" "${PROGRESSA_BUILD_NUMBER}"
fi

echo "Building TestFlight IPAs"
echo "Export method: ${EXPORT_METHOD}"
echo "Quantivita API: ${QUANTIVITA_API_BASE_URL}"
echo "Progressa auth: ${PROGRESSA_AUTH_BASE_URL}"
echo "Progressa connect API: ${PROGRESSA_CONNECT_API_BASE_URL}"

if [[ "${BUILD_QUANTIVITA}" == "1" ]]; then
  echo
  echo "=== Quantivita ${QUANTIVITA_VERSION} (${QUANTIVITA_BUILD_NUMBER}) ==="
  quantivita_args=(
    --version "${QUANTIVITA_VERSION}"
    --build-number "${QUANTIVITA_BUILD_NUMBER}"
    --export-method "${EXPORT_METHOD}"
  )
  if [[ "${RUN_CLEAN}" == "0" ]]; then
    quantivita_args+=(--no-clean)
  fi
  if [[ "${RUN_PUB_GET}" == "0" ]]; then
    quantivita_args+=(--no-pub-get)
  fi
  if [[ "${RUN_ASC_CHECK}" == "0" ]]; then
    quantivita_args+=(--skip-asc-check)
  fi

  (
    cd "${QUANTIVITA_DIR}"
    QUANTIVITA_API_BASE_URL="${QUANTIVITA_API_BASE_URL}" \
    PROGRESSA_AUTH_BASE_URL="${PROGRESSA_AUTH_BASE_URL}" \
    ./scripts/build_testflight_ipa.sh "${quantivita_args[@]}"
  )
fi

if [[ "${BUILD_PROGRESSA}" == "1" ]]; then
  echo
  echo "=== Progressa ${PROGRESSA_VERSION} (${PROGRESSA_BUILD_NUMBER}) ==="
  (
    cd "${PROGRESSA_DIR}"

    if [[ "${RUN_CLEAN}" == "1" ]]; then
      run_step flutter clean
    fi

    if [[ "${RUN_PUB_GET}" == "1" ]]; then
      run_step flutter pub get
    fi

    if flutter pub deps --style=compact > /tmp/progressa_deps.txt 2>/dev/null &&
       grep -q "flutter_native_splash" /tmp/progressa_deps.txt; then
      run_step dart run flutter_native_splash:create
    fi

    if flutter pub deps --style=compact > /tmp/progressa_deps.txt 2>/dev/null &&
       grep -q "flutter_launcher_icons" /tmp/progressa_deps.txt; then
      run_step dart run flutter_launcher_icons
    else
      echo
      echo "==> flutter_launcher_icons not installed; skipping icon generation"
    fi

    if [[ -d ios ]]; then
      echo
      echo "==> pod install"
      (cd ios && pod install)
    fi

    rm -rf build/ios/archive build/ios/ipa

    run_step flutter build ipa \
      --release \
      --build-name="${PROGRESSA_VERSION}" \
      --build-number="${PROGRESSA_BUILD_NUMBER}" \
      --dart-define-from-file=env.json \
      --dart-define="PROGRESSA_CONNECT_API_BASE_URL=${PROGRESSA_CONNECT_API_BASE_URL}" \
      --export-method "${EXPORT_METHOD}"
  )
fi

echo
echo "Build complete."
echo "IPA output:"
if [[ -d "${QUANTIVITA_DIR}/build/ios/ipa" ]]; then
  find "${QUANTIVITA_DIR}/build/ios/ipa" -maxdepth 1 -name '*.ipa' -print
fi
if [[ -d "${PROGRESSA_DIR}/build/ios/ipa" ]]; then
  find "${PROGRESSA_DIR}/build/ios/ipa" -maxdepth 1 -name '*.ipa' -print
fi
