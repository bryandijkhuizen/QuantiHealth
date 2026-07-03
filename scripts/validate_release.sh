#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: scripts/validate_release.sh x.y.z" >&2
  exit 2
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ ! "${BRANCH}" =~ ^release/.+-${VERSION}$ && ! "${BRANCH}" =~ ^release/${VERSION}$ && ! "${BRANCH}" =~ ^hotfix/ ]]; then
  echo "Run release validation from release/<target>-${VERSION}, release/${VERSION}, or a hotfix/* branch. Current branch: ${BRANCH}" >&2
  exit 2
fi

echo "Validating release ${VERSION}..."

if command -v jq >/dev/null 2>&1; then
  jq -e '.apps | length > 0' release/apps.json >/dev/null
  jq -e '.services | length > 0' release/services.json >/dev/null
else
  echo "jq is recommended for release manifest validation; skipping JSON validation."
fi

if [[ -d services/quantivita-mcp/server ]]; then
  (cd services/quantivita-mcp/server && npm test)
fi

echo
echo "Release ${VERSION} validation passed."
echo "Before tagging, confirm app versions, build numbers, changelog, release notes, and archive/TestFlight build."
