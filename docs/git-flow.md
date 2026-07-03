# QuantiHealth Git Flow

This workspace uses one shared branch flow for every Quanti app and service.
Each release target has its own version number and tag prefix.

## Branches

- `main`: stable release branch. Deploys are allowed only from release tags or manual workflow dispatch.
- `develop`: integration branch for the next version.
- `feature/<short-description>`: feature work from `develop`.
- `fix/<short-description>`: small fixes from `develop`.
- `hotfix/<short-description>`: urgent production fixes from `main`.
- `release/<version>`: release preparation from `develop`.

## Versions

Use strict semantic versioning:

- `x.0.0`: major release.
- `x.y.0`: feature release.
- `x.y.z`: patch or hotfix release.

Do not use one global version for the whole workspace.

Use target-specific tags:

- Quantivita iOS: `quantivita-native-ios-v<version>`
- Progressa iOS: `progressa-native-ios-v<version>`
- Quantivita MCP / homeserver: `quantivita-mcp-v<version>`

Example:

```bash
git tag quantivita-native-ios-v0.1.0
git tag quantivita-mcp-v0.2.0
```

## Release Targets

App-specific release metadata lives in `release/apps.json`.
Service-specific release metadata lives in `release/services.json`.

Each app entry defines:

- app name
- app path
- platform type (`native-ios`)
- scheme
- current version
- bundle identifier
- Apple team id
- optional test command

GitHub Actions uses these manifests so every Quanti target follows the same branch rules without copy-pasted workflows.

## Feature Flow

```bash
git checkout develop
git pull origin develop
git checkout -b feature/workout-wizard

# work, test, commit
git push origin feature/workout-wizard
```

Open a PR into `develop`.

## Fix Flow

```bash
git checkout develop
git pull origin develop
git checkout -b fix/mcp-coverage-fields

# work, test, commit
git push origin fix/mcp-coverage-fields
```

Open a PR into `develop`.

## App Release Flow

```bash
git checkout develop
git pull origin develop
git checkout -b release/quantivita-native-ios-0.1.0

scripts/validate_release.sh 0.1.0

git push origin release/quantivita-native-ios-0.1.0
```

Open a PR into `main`. After merge:

```bash
git checkout main
git pull origin main
git tag quantivita-native-ios-v0.1.0
git push origin main --tags

git checkout develop
git pull origin develop
git merge --no-ff main
git push origin develop
```

## MCP / Homeserver Release Flow

The Quantivita MCP server is versioned independently from the apps.
Its version source is `services/quantivita-mcp/server/package.json`.

Use MCP-specific release branches and tags:

```bash
git checkout develop
git pull origin develop
git checkout -b release/quantivita-mcp-0.2.0

cd services/quantivita-mcp/server
npm version 0.2.0 --no-git-tag-version
npm test
cd ../../..

git add services/quantivita-mcp/server/package.json services/quantivita-mcp/server/package-lock.json
git commit -m "Prepare Quantivita MCP 0.2.0"
git push origin release/quantivita-mcp-0.2.0
```

Open a PR into `main`. After merge:

```bash
git checkout main
git pull origin main
git tag quantivita-mcp-v0.2.0
git push origin main --tags
```

The `quantivita-mcp-v*.*.*` tag triggers `.github/workflows/deploy-quantivita-mcp.yml`.

## Hotfix Flow

```bash
git checkout main
git pull origin main
git checkout -b hotfix/app-crash-on-launch

# work, test, commit
git push origin hotfix/app-crash-on-launch
```

Open a PR into `main`, tag the patch release after merge, then merge `main` back into `develop`.

## Required GitHub Secrets

Shared:

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `MATCH_PASSWORD`
- `MATCH_GIT_URL`
- `MATCH_GIT_BASIC_AUTHORIZATION`

MCP deploy:

- `QUANTIVITA_HOMESERVER_HOST`
- `QUANTIVITA_HOMESERVER_USER`
- `QUANTIVITA_HOMESERVER_DIR`
- `QUANTIVITA_HOMESERVER_SSH_KEY`
- `QUANTIVITA_PUBLIC_BASE_URL`
- `QUANTIVITA_SESSION_SECRET`
- `APPLE_WEB_CLIENT_ID`
- `PROGRESSA_API_BASE_URL`
- `STRAVA_CLIENT_ID`
- `STRAVA_CLIENT_SECRET`
- `STRAVA_REDIRECT_URI`
- `STRAVA_API_BASE_URL`

## Branch Protection

Run `scripts/configure_branch_protection.sh owner/repo` after the GitHub repo exists and `gh auth status` passes.
