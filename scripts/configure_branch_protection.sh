#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
if [[ -z "${REPO}" ]]; then
  echo "Usage: scripts/configure_branch_protection.sh owner/repo" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 127
fi

gh auth status >/dev/null

protect_branch() {
  local branch="$1"
  local contexts_json="$2"
  gh api \
    --method PUT \
    "repos/${REPO}/branches/${branch}/protection" \
    --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ${contexts_json}
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": true
}
JSON
}

protect_branch "main" '["Quantivita Server Tests","Validate App Matrix"]'
protect_branch "develop" '["Quantivita Server Tests","Validate App Matrix"]'

echo "Branch protection configured for ${REPO}: main and develop."

