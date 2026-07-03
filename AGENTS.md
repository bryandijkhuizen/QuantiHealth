## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, invoke the `skill` tool with `skill: "graphify"` before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## QuantiHealth AI agent runbook

Every code AI working here must follow the same repository process.

Start by reading:
- `docs/ai-agent-runbook.md`
- `docs/git-flow.md`
- `release/apps.json`
- `release/services.json`

Branch rules:
- Normal feature work starts from `develop` on `feature/*`.
- Small fixes start from `develop` on `fix/*`.
- Production hotfixes start from `main` on `hotfix/*`.
- Releases start from `develop` on `release/<target>-<version>`.
- Do not put feature work directly on `main`.

Version rules:
- Quantivita iOS starts at `0.1.0`.
- Progressa iOS starts at `2.0.0`.
- Quantivita MCP/homeserver has its own independent version in `services/quantivita-mcp/server/package.json`.
- Do not use global workspace tags such as `v1.0.0`.
- Use target tags from the manifests:
  - `quantivita-native-ios-v<version>`
  - `progressa-native-ios-v<version>`
  - `quantivita-mcp-v<version>`

Deploy rules:
- Native app TestFlight deploys use `.github/workflows/testflight.yml`.
- Quantivita MCP/homeserver deploys use `.github/workflows/deploy-quantivita-mcp.yml`.
- Never hardcode secrets. Use GitHub Secrets listed in `docs/git-flow.md`.

Validation rules:
- Run the smallest relevant target tests.
- For MCP/server changes, run `npm test` in `services/quantivita-mcp/server`.
- After code changes, run `graphify update .`.
- Before committing, check `git status --short` and avoid staging secrets, build output, `node_modules/`, `Pods/`, `graphify-out/`, local notes, or nested standalone repos.
