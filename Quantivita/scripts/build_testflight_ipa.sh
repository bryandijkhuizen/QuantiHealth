#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/load_env.sh
load_quantivita_env "$(pwd)"

usage() {
  cat <<'EOF' 
Usage: scripts/build_testflight_ipa.sh [options]

Builds a signed iOS .ipa for TestFlight/App Store Connect.

Defaults:
  Version:       0.0.3
  Build number: 1
  Export method: app-store

Options:
  --version VERSION          CFBundleShortVersionString, default 0.0.3
  --build-number NUMBER      CFBundleVersion, default 1
  --export-method METHOD     app-store, ad-hoc, development, or enterprise
  --no-clean                 Skip flutter clean before building
  --no-pub-get               Skip flutter pub get
  --skip-xcode-first-launch  Do not run xcodebuild -runFirstLaunch
  --skip-asc-check           Do not check App Store Connect access/agreements
  -h, --help                 Show help

Environment variables are loaded from .env by default:
  QUANTIVITA_IOS_BUILD_NAME
  QUANTIVITA_IOS_BUILD_NUMBER
  QUANTIVITA_IOS_EXPORT_METHOD
  QUANTIVITA_API_BASE_URL
  STRAVA_CLIENT_ID
  STRAVA_CLIENT_SECRET
  STRAVA_REDIRECT_URI
  APP_STORE_CONNECT_API_KEY
  APP_STORE_CONNECT_API_ISSUER
  APP_STORE_CONNECT_API_KEY_PATH
  APP_STORE_CONNECT_PROVIDER_PUBLIC_ID

Override the env file with:
  QUANTIVITA_ENV_FILE=/path/to/.env scripts/build_testflight_ipa.sh
EOF
}

BUILD_NAME="${QUANTIVITA_IOS_BUILD_NAME:-0.0.3}"
BUILD_NUMBER="${QUANTIVITA_IOS_BUILD_NUMBER:-1}"
EXPORT_METHOD="${QUANTIVITA_IOS_EXPORT_METHOD:-app-store}"
RUN_CLEAN=1
RUN_PUB_GET=1
RUN_XCODE_FIRST_LAUNCH=1
RUN_ASC_CHECK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      BUILD_NAME="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
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
    --skip-xcode-first-launch)
      RUN_XCODE_FIRST_LAUNCH=0
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

if [[ ! "${BUILD_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "--version must look like x.y.z, got '${BUILD_NAME}'." >&2
  exit 2
fi

if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "--build-number must be an integer, got '${BUILD_NUMBER}'." >&2
  exit 2
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH." >&2
  exit 127
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install/open Xcode first." >&2
  exit 127
fi

ASC_AGREEMENTS_URL="https://appstoreconnect.apple.com/agreements/"

run_xcode_first_launch() {
  if [[ "${RUN_XCODE_FIRST_LAUNCH}" != "1" ]]; then
    return 0
  fi

  echo
  echo "Checking Xcode first-launch tasks and local Xcode/SDK licence..."
  if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    echo "Xcode first-launch status: OK"
    return 0
  fi

  echo "Running xcodebuild -runFirstLaunch..."
  if xcodebuild -runFirstLaunch >/dev/null; then
    echo "Xcode first-launch tasks completed."
    return 0
  fi

  cat >&2 <<'EOF'
Xcode first-launch/licence step failed.
Run this once manually if macOS asks for admin rights:

  sudo xcodebuild -runFirstLaunch

Then rerun:

  scripts/build_testflight_ipa.sh
EOF
  exit 1
}

check_app_store_connect_agreements() {
  if [[ "${RUN_ASC_CHECK}" != "1" ]]; then
    return 0
  fi

  if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" || -z "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
    cat <<EOF

App Store Connect agreement preflight: skipped.
Set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER in .env to let
this script check App Store Connect access before the IPA build.

Legal App Store Connect agreements cannot be accepted safely by this script.
If Apple says agreements are pending, accept them here:
  ${ASC_AGREEMENTS_URL}
EOF
    return 0
  fi

  echo
  echo "Checking App Store Connect access and pending agreements..."
  local altool_args=(
    --list-providers
    --api-key "${APP_STORE_CONNECT_API_KEY}"
    --api-issuer "${APP_STORE_CONNECT_API_ISSUER}"
  )

  if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
    altool_args+=(--p8-file-path "${APP_STORE_CONNECT_API_KEY_PATH}")
  fi

  local output
  if output="$(xcrun altool "${altool_args[@]}" 2>&1)"; then
    echo "App Store Connect access: OK"
    return 0
  fi

  echo "${output}" >&2
  if echo "${output}" | grep -Eiq 'agreement|contract|license|licence|terms'; then
    cat >&2 <<EOF

App Store Connect has a pending agreement/contract/terms step.
This must be accepted manually by the account holder:
  ${ASC_AGREEMENTS_URL}
EOF
    if command -v open >/dev/null 2>&1; then
      open "${ASC_AGREEMENTS_URL}" >/dev/null 2>&1 || true
    fi
  fi
  exit 1
}

if [[ -n "${QUANTIVITA_API_BASE_URL:-}" ]]; then
  API_BASE_URL="${QUANTIVITA_API_BASE_URL}"
else
  API_BASE_URL="https://api.quantivita.bryandijkh.com"
fi

ARGS=(
  build
  ipa
  --release
  --build-name="${BUILD_NAME}"
  --build-number="${BUILD_NUMBER}"
  --export-method="${EXPORT_METHOD}"
  --dart-define="QUANTIVITA_API_BASE_URL=${API_BASE_URL}"
)

if [[ "${RUN_PUB_GET}" == "0" ]]; then
  ARGS+=(--no-pub)
fi

if [[ -n "${STRAVA_CLIENT_ID:-}" ]]; then
  ARGS+=(--dart-define="STRAVA_CLIENT_ID=${STRAVA_CLIENT_ID}")
fi

if [[ -n "${STRAVA_CLIENT_SECRET:-}" ]]; then
  ARGS+=(--dart-define="STRAVA_CLIENT_SECRET=${STRAVA_CLIENT_SECRET}")
fi

if [[ -n "${STRAVA_REDIRECT_URI:-}" ]]; then
  ARGS+=(--dart-define="STRAVA_REDIRECT_URI=${STRAVA_REDIRECT_URI}")
fi

echo "Building Quantivita TestFlight IPA..."
echo "Version: ${BUILD_NAME} (${BUILD_NUMBER})"
echo "Export method: ${EXPORT_METHOD}"
echo "API: ${API_BASE_URL}"

if [[ -n "${STRAVA_CLIENT_ID:-}" ]]; then
  echo "Strava: configured for client ${STRAVA_CLIENT_ID}"
else
  echo "Strava: not configured"
fi

run_xcode_first_launch
check_app_store_connect_agreements

if [[ "${RUN_CLEAN}" == "1" ]]; then
  echo
  echo "Cleaning Flutter build output..."
  rtk flutter clean
fi

if [[ "${RUN_PUB_GET}" == "1" ]]; then
  echo
  echo "Fetching Flutter dependencies..."
  rtk flutter pub get
fi

echo
echo "Creating signed IPA..."
rtk flutter "${ARGS[@]}"

IPA_DIR="build/ios/ipa"
echo
echo "Build complete."
if [[ -d "${IPA_DIR}" ]]; then
  echo "IPA output:"
  find "${IPA_DIR}" -maxdepth 1 -name '*.ipa' -print
else
  echo "Expected IPA directory not found: ${IPA_DIR}" >&2
fi
