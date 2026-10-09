# Changelog

## 0.1.1 - 2026-10-08

- 0.1.1: git-guard hook; run-report 0.2.2; graph-node 0.2.1
- Skills git-guard 0.1.0, run-report 0.2.2 and graph-node 0.2.1 copied from Graph HEAD; git-guard's PreToolUse hook merged into `.claude/settings.json`. `tests/Skills.Tests.ps1` checks each copy's version and full text against `git show HEAD:` in Graph, and the hook's exit codes (0, 0, 2, 2, 2, 2 for git status, git add, git commit, git push, git tag, gh pr merge).
- `artifacts/` gitignored; skills `readme` and `tool-map` at 0.1.1 with the module; `ledger-writer` recopied at Claude.Agent.Ledger 0.2.2 (version only, the README sections it copies are unchanged).

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
