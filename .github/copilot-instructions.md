# Copilot Instructions for QuantiHealth

Follow `AGENTS.md`, `docs/ai-agent-runbook.md`, and `docs/git-flow.md`.

Important rules:

- Work from `develop` unless doing a hotfix from `main`.
- Use `feature/*`, `fix/*`, `hotfix/*`, and `release/<target>-<version>` branches.
- Quantivita iOS starts at `0.1.0`.
- Progressa iOS starts at `2.0.0`.
- The Quantivita MCP/homeserver has its own independent version.
- Use target-specific tags:
  - `quantivita-native-ios-v<version>`
  - `progressa-native-ios-v<version>`
  - `quantivita-mcp-v<version>`
- Native apps deploy to TestFlight through `.github/workflows/testflight.yml`.
- MCP deploys through `.github/workflows/deploy-quantivita-mcp.yml`.
- Never hardcode secrets.
- Update `release/apps.json` and `release/services.json` when targets change.

