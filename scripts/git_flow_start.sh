#!/usr/bin/env bash
set -euo pipefail

TYPE="${1:-}"
NAME="${2:-}"

case "${TYPE}" in
  feature|fix)
    BASE="develop"
    ;;
  hotfix)
    BASE="main"
    ;;
  release)
    BASE="develop"
    if [[ ! "${NAME}" =~ ^([a-z0-9-]+-)?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Release branch names must be versions like 1.1.0 or target-prefixed names like quantivita-mcp-0.2.0." >&2
      exit 2
    fi
    ;;
  *)
    echo "Usage: scripts/git_flow_start.sh feature|fix|hotfix|release short-name" >&2
    exit 2
    ;;
esac

if [[ -z "${NAME}" ]]; then
  echo "Missing branch short-name/version." >&2
  exit 2
fi

git checkout "${BASE}"
git pull --ff-only origin "${BASE}" 2>/dev/null || true
git checkout -b "${TYPE}/${NAME}"
