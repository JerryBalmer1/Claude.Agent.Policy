# Claude.Agent.Policy

What a Claude.Agent container may do with Claude Code's tools, as a file. `New-Policy` writes `policy.json`
at image build from the `actions` blocks of emitter ontologies; a PreToolUse hook decides every tool call
against it, blocks a deny with exit 2, and spools every decision to Claude.Agent.Ledger as
`policy.allow`, `policy.deny` or `policy.witness`.

Requires PowerShell 7.4+. No external dependencies. The hooks also need Claude.Agent.Ledger.

## Policy

```json
{ "version": 1, "generated": "2026-10-09T00:53:38Z", "default": "deny", "rules": [
  { "kind": "Directory", "action": "delete", "effect": "deny" },
  { "kind": "Directory", "action": "read",   "effect": "allow" },
  { "kind": "File",      "action": "delete", "effect": "deny" },
  { "kind": "File",      "action": "read",   "effect": "allow" },
  { "kind": "File",      "action": "write",  "effect": "allow", "paths": ["/work/**"] },
  { "kind": "Shell",     "action": "exec",   "effect": "witness" } ] }
```

That is the policy generated from Graph.Emitter.FileSystem's ontology. Schema: `schemas/policy.schema.json`.

- One rule per `Kind.action` declared by the ontologies passed to New-Policy plus `ontology/claude-code.yaml`
  (the actions Claude Code's tools map to; [design 1](docs/design.md)). Each rule's effect, and paths if any,
  come from `src/Claude.Agent.Policy/policy.defaults.json`: `byKindAction` first, then `byAction`.
- Effects: `allow`; `deny`; `witness` (allowed, ledgered as `policy.witness`).
- Matching: the first rule for the call's `Kind.action` whose `paths` match decides; a rule without `paths`
  matches any target. No match means `default`, which the schema pins to `deny`. Paths are absolute POSIX
  globs (`**` crosses `/`, `*` and `?` do not, `dir/**` also matches `dir`); targets are normalised
  ([design 3](docs/design.md)).

| Claude Code tool | Kind.action |
| --- | --- |
| Read | File.read |
| Edit, MultiEdit, Write, NotebookEdit | File.write |
| Glob, Grep, LS | Directory.read |
| Bash running `rm`, `unlink`, `shred`, `rmdir`, `find -delete` | File.delete, or Directory.delete ([design 2](docs/design.md)) |
| Bash, anything else | Shell.exec |
| anything else | none: `default` (deny) |

## Functions

| Function | What it does |
| --- | --- |
| `New-Policy -OntologyPath <yaml[]> [-DefaultsPath <json>] [-OutPath <json>] [-SchemaPath <json>]` | Builds the policy above, runs Test-Policy on it, writes `-OutPath` if given, returns it. Throws if a declared action has no default. |
| `Test-Policy -Path <policy.json or object> -OntologyPath <yaml[]> [-SchemaPath <json>]` | Returns `$true`, or throws listing every schema error and every rule whose `Kind.action` no ontology declares. |
| `Resolve-PolicyDecision -Tool <name> -Input <tool_input> [-Cwd <dir>] [-Policy <path or object>]` | Returns `{effect, rule, reason, tool, kindAction, path, command, targets}`. `rule` is `rules[n]` or `default`. `-Policy` defaults to `$env:CLAUDE_AGENT_POLICY`, else `/opt/agent/policy/policy.json`. |

`-Input` takes the hook payload's `tool_input` as a hashtable, an object or JSON text.

```powershell
Import-Module ./src/Claude.Agent.Policy
$p = New-Policy -OntologyPath tests/fixtures/Graph.Emitter.FileSystem.ontology.yaml
(Resolve-PolicyDecision -Tool Write -Input @{ file_path = '/work/../etc/x' } -Cwd /work -Policy $p).reason
# File.write /etc/x matches no rule for File.write; policy default is deny
(Resolve-PolicyDecision -Tool Bash -Input @{ command = 'rm -f /work/out.txt' } -Cwd /work -Policy $p).reason
# File.delete /work/out.txt denied by policy rules[2]
```

## Hooks

`hooks/settings.json` wires both for every tool (`"matcher": "*"`), as
`pwsh -NoProfile -NonInteractive -File /opt/agent/policy/hooks/<name>.ps1`. Each reads Claude Code's hook
payload from stdin and takes the policy from `$env:CLAUDE_AGENT_POLICY`, else `policy.json` one directory up,
and the spool from `$env:CLAUDE_AGENT_SPOOL`, else `/spool`.

| Hook | Allow / witness | Deny | Error |
| --- | --- | --- | --- |
| `pre-tool-use.ps1` | exit 0, stdout `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",...}}` | exit 2, reason on stderr | exit 2 (fails closed, [design 4](docs/design.md)) |
| `post-tool-use.ps1` | exit 0 | exit 0 | exit 0, message on stderr |

Each spools one entry with `Add-LedgerEntry -Spool`, kind `policy.allow`, `policy.deny` or `policy.witness`, body:

| Field | Value |
| --- | --- |
| `phase` | `pre` or `post` |
| `tool` | Claude Code's tool name |
| `kindAction` | e.g. `File.delete`; null for an unmapped tool |
| `path` | the normalised target that decided; null for Shell.exec |
| `rule` | `rules[n]` or `default` |
| `reason` | pre only |
| `command` | Bash only, verbatim |

## How Claude.Agent bakes it in

Claude.Agent's Modules task copies `src/Claude.Agent.Policy` (with `schemas/` added inside it) into the image's
module path and `hooks/` into `build/policy/`. The agent Dockerfile then runs `New-Policy` against its vendored
copy of Graph.Emitter.FileSystem's ontology, `Test-Policy`, and leaves `/opt/agent/policy/{policy.json,
settings.json, hooks/, ontology/}` owned by root, read-only. The entrypoint merges `settings.json` into
`~/.claude/settings.json` before `claude -p`. Claude.Agent's Smoke task requires allow, allow, deny for a
read, a write under `/work` and a delete, and the file to survive.

## Development

```powershell
Invoke-Build          # runs Pester via pwsh -NoProfile -File tests/Invoke-Tests.ps1
```

The hook tests start real `pwsh` processes and import Claude.Agent.Ledger from `../Claude.Agent.Ledger/src`.
`tests/fixtures/Graph.Emitter.FileSystem.ontology.yaml` is a copy; Pester checks it against
`../Graph.Emitter.FileSystem/ontology.yaml` when that checkout exists.

See [docs/design.md](docs/design.md) for the decisions behind this.
