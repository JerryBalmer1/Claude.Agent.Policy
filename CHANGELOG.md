# Changelog

## 0.1.0 - 2026-10-08

- `New-Policy -OntologyPath <yaml[]> [-DefaultsPath] [-OutPath] [-SchemaPath]`: one rule per Kind.action
  declared in the ontologies' `actions` blocks plus the module's `ontology/claude-code.yaml`, each set from
  `policy.defaults.json` (read allow, write allow under `/work/**`, delete deny, `Shell.exec` witness, default deny).
  A declared action with no default throws.
- `Test-Policy -Path <policy.json | object> -OntologyPath <yaml[]> [-SchemaPath]`: `schemas/policy.schema.json`
  plus no rule for an undeclared Kind.action; throws listing every problem.
- `Resolve-PolicyDecision -Tool -Input [-Cwd] [-Policy]` -> `{effect, rule, reason}` plus `tool`, `kindAction`,
  `path`, `command`, `targets`. Claude Code tools map per design 1; Bash deletes are classified per design 2.
- `hooks/pre-tool-use.ps1` (exit 2 with the reason on deny, exit 0 with `permissionDecision: allow` otherwise,
  fails closed), `hooks/post-tool-use.ps1`, `hooks/settings.json` (PreToolUse and PostToolUse, matcher `*`).
  Both spool `policy.allow | policy.deny | policy.witness` via `Add-LedgerEntry -Spool`, body
  `{phase, tool, kindAction, path, rule, reason?, command?}`.
- Skills: `ledger-writer` (copied from Claude.Agent.Ledger 0.2.1), `readme`, `tool-map`; Pester checks each
  skill's front-matter version against its source module.
- Pester: 39 tests (policy, hooks run as real pwsh processes, module and skills).
