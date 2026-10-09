# CLAUDE.md

PowerShell 7.4+ module plus two Claude Code hooks: a tool policy generated from emitter ontologies at image
build, enforced on every tool call by a PreToolUse hook, and every decision spooled to Claude.Agent.Ledger.
One of four sibling repos:

- `Claude.Agent` builds the agent image: it copies `src/Claude.Agent.Policy`, `schemas/` and `hooks/` from here,
  runs New-Policy against its vendored Graph.Emitter.FileSystem ontology, and bakes the result read-only at `/opt/agent/policy`.
- `Claude.Agent.Ledger` is the ledger; the hooks use its writer side (`Add-LedgerEntry -Spool`) only.
- `Claude.Agent.Network` is the mitmproxy capture sidecar.
- `Claude.Agent.Policy` (this repo).

All are expected side by side (e.g. `C:\__Code\`). The hook tests import Claude.Agent.Ledger from `../Claude.Agent.Ledger/src`.

## Layout

- `src/Claude.Agent.Policy/` module. `Public/*.ps1` are exported (list them in the `.psd1` too), `Private/*.ps1`
  are helpers. `policy.defaults.json` and `ontology/claude-code.yaml` ship inside the module.
- `schemas/policy.schema.json` the policy contract. `hooks/` the two hooks and the settings fragment.
- `tests/` Pester 5+. Run through `tests/Invoke-Tests.ps1`. `tests/fixtures/` holds a copy of Graph.Emitter.FileSystem's ontology.
- `docs/design.md` numbered decisions. Add an entry when you make a decision someone could reasonably reverse.
- `.claude/skills/`: `readme`, `tool-map` (this repo's), `ledger-writer` (copied from Claude.Agent.Ledger, read-only here).

## Commands

- `Invoke-Build` runs the Pester task (default).
- Run Pester only as `pwsh -NoProfile -File tests/Invoke-Tests.ps1`.

## Rules

- Fail closed. Only exit 2 blocks a Claude Code call; the pre hook must turn every error into exit 2.
- The tool map lives in five places (see the `tool-map` skill); change them together.
- `default` is `deny` and the schema pins it. A policy that allows by default is a design change, not a setting.
- Keep the module dependency-free; it runs inside the agent image on every tool call. The YAML reader reads only
  `kinds.<Kind>.actions[].name`; Graph.Node's validator owns full ontology validation.
- Never give the hooks a path to the ledger directory or key; they write to the spool only.
