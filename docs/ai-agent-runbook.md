# AI Agent Runbook

This is the handoff guide for Codex, Claude, Copilot, and other code AI agents working in QuantiHealth.

## Repository Shape

- This directory is the QuantiHealth monorepo.
- Active TestFlight apps:
  - `QuantivitaNative`, version starts at `0.1.0`
  - `ProgressaNative`, version starts at `2.0.0`
- Active service:
  - `services/quantivita-mcp/server`, versioned independently from apps
- Flutter app archives have been removed from this repo.
- `Progressa/progressa-landing-page/progressa-landing/` is a standalone nested repo and is ignored here.

## First Checks

```bash
git branch --show-current
git status --short
cat release/apps.json
cat release/services.json
```

For codebase questions, use Graphify first:

```bash
graphify query "<question>"
```

## Branches

- `feature/<short-description>` from `develop`
- `fix/<short-description>` from `develop`
- `hotfix/<short-description>` from `main`
- `release/<target>-<version>` from `develop`

Helper:

```bash
scripts/git_flow_start.sh feature workout-polish
scripts/git_flow_start.sh fix mcp-missing-days
scripts/git_flow_start.sh release progressa-native-ios-2.0.0
scripts/git_flow_start.sh release quantivita-mcp-0.2.1
```

## Release Tags

Use only target-specific tags:

- `quantivita-native-ios-v<version>`
- `progressa-native-ios-v<version>`
- `quantivita-mcp-v<version>`

Do not create a global `v<version>` tag.

## TestFlight

App metadata lives in `release/apps.json`.

After merging a release branch into `main`, tag the target:

```bash
git tag quantivita-native-ios-v0.1.0
git push origin main --tags
```

or:

```bash
git tag progressa-native-ios-v2.0.0
git push origin main --tags
```

These tags trigger `.github/workflows/testflight.yml`.

## MCP / Homeserver

MCP metadata lives in `release/services.json`.

Version file:

```txt
services/quantivita-mcp/server/package.json
```

Release example:

```bash
git checkout develop
git checkout -b release/quantivita-mcp-0.2.1
cd services/quantivita-mcp/server
npm version 0.2.1 --no-git-tag-version
npm test
cd ../../..
git add services/quantivita-mcp/server/package.json services/quantivita-mcp/server/package-lock.json
git commit -m "Prepare Quantivita MCP 0.2.1"
```

After merge to `main`:

```bash
git tag quantivita-mcp-v0.2.1
git push origin main --tags
```

This tag triggers `.github/workflows/deploy-quantivita-mcp.yml`.

## Local Validation

Use what matches the touched target:

```bash
cd services/quantivita-mcp/server && npm test
```

```bash
jq -e '.apps | length > 0 and all(.[]; .id and .path and .platform and .scheme and .tagPrefix and .currentVersion and .bundleIdentifierSecret)' release/apps.json
jq -e '.services | length > 0 and all(.[]; .id and .path and .tagPrefix and .versionFile and .testCommand)' release/services.json
```

```bash
bash -n scripts/*.sh
ruby -c fastlane/Fastfile
ruby -c fastlane/Appfile
```

After code changes:

```bash
graphify update .
```

## GitHub Setup

There may be no remote yet. Check with:

```bash
git remote -v
```

When a GitHub repo exists:

```bash
git remote add origin <git-url>
git push -u origin main
git push -u origin develop
scripts/configure_branch_protection.sh owner/repo
```

Required secrets are listed in `docs/git-flow.md`.

