# Design decisions

## 1. Claude Code tools map onto ontology Kind.actions

A policy speaks the emitters' language, `Kind.action` from the `actions` blocks of an `ontology.yaml`, not
Claude Code's tool names. That way one policy covers whatever performs the action: Claude Code today, an
emitter's own verb (Graph.Emitter.FileSystem's `Remove-FileSystemItem` is `File.delete`) later. The map:

| Claude Code tool | Kind.action | Target path from `tool_input` |
| --- | --- | --- |
| Read | File.read | `file_path` |
| Edit, MultiEdit, Write | File.write | `file_path` |
| NotebookEdit | File.write | `notebook_path` |
| Glob, Grep, LS | Directory.read | `path`, else the hook's `cwd` |
| Bash, recognised delete (decision 2) | File.delete, or Directory.delete when recursive or `rmdir` | each operand |
| Bash, anything else | Shell.exec | none |
| any other tool (WebFetch, Task, TodoWrite, MCP tools, ...) | none | none: the policy default, deny |

Graph.Emitter.FileSystem declares only `File.delete` and `Directory.delete`. The other four the map produces
are declared by this module's `ontology/claude-code.yaml`, in the same shape, which New-Policy and Test-Policy
always read alongside the ontologies they are given. When an emitter declares one of them, it moves out of
`claude-code.yaml`. A tool with no mapping is denied, so a new Claude Code tool is refused until someone maps it
here; NotebookEdit, MultiEdit and LS are mapped because they do the same thing as a mapped tool.

## 2. Deletes come through Bash, so Bash is classified, lexically

Claude Code has no delete tool. Mapping Bash to `Shell.exec` alone would make `File.delete: deny` dead
policy, since `rm` would arrive as a witnessed `Shell.exec`. So the resolver splits a Bash command into simple
commands (on `;`, `&`, `|`, `&&`, `||`, newlines, parentheses), strips quotes, skips env assignments and
wrappers (`sudo`, `env`, `xargs`, `busybox`, ...), and treats `rm`, `unlink`, `shred`, `rmdir` and
`find ... -delete` as deletes of their operands. Several targets in one command are decided separately and the
strictest wins (deny, then witness, then allow).

This is a best-effort lexical match, not a sandbox. It does not see `python -c 'os.remove(...)'`,
`node -e`, `mv x /dev/null`, `git clean`, `$(...)`, variables, or a script file that deletes. Those run as
`Shell.exec`, which is witnessed: every Bash command is ledgered verbatim, allowed or not. The real fences for
what Bash can do are the container's: the agent runs as uid 10001, `/opt/agent/policy` is root-owned and
read-only, and the ledger key is in another container.

## 3. Paths: normalised, symlinks resolved on Linux, globs anchored

A target path is made absolute against the hook's `cwd`, `.` and `..` are folded, `~` is `$HOME`, and on Linux
`realpath -m` resolves symlinks in the part that exists, so `/work/link-to-etc/passwd` is judged as
`/etc/passwd`. Globs are anchored POSIX globs: `**` crosses `/`, `*` and `?` do not, and `dir/**` also matches
`dir`. A rule with `paths` never matches a target whose path is unknown (e.g. `xargs rm`); a rule without
`paths` matches any target. So a write with no path falls to the default, deny.

`realpath` runs at decision time, so a symlink created after the decision and before the tool runs is not
seen. Closing that needs the tool itself to refuse, which Claude Code's hooks cannot do.

## 4. The pre hook is the permission authority, and fails closed

On allow or witness the pre hook exits 0 and prints `permissionDecision: allow`, so Claude Code does not fall
back to its own prompt (there is nobody to answer one in `claude -p`). On deny it exits 2 with the reason on
stderr, which Claude Code shows the model. Exit 2 is the only exit that blocks; any other non-zero exit lets the
call through. So every failure in the pre hook (no policy, bad payload, the spool write failing) is caught and
turned into exit 2: a call that cannot be decided and recorded does not run.

Reversible: dropping the `permissionDecision` output puts Claude Code's own permission rules back as a second
gate after the policy, at the price of `--allowedTools` or a permission mode in every `claude -p`.

## 5. Every decision is ledgered, before and after

The pre hook spools `policy.<effect>` with `phase: pre` before it answers; the post hook spools the same
decision with `phase: post` after the call ran. A pre entry with no post means the call was refused or failed;
a `post` entry with `policy.deny` means something ran that the policy refuses, which Claude.Agent's Smoke
asserts never happens. Body fields: `phase`, `tool`, `kindAction`, `path`, `rule` (`rules[n]` or `default`),
`reason` (pre only), `command` (Bash only).

The agent writes these entries, so the agent can omit or alter them before the keeper chains them
(Claude.Agent.Ledger design 3). They record what the hook decided; they do not prove the hook saw every call.

## 6. Settings go in the agent's user settings, not managed settings (for now)

The hook fragment is merged into `~/.claude/settings.json` at container start, as asked. The agent user owns
that file, so a Bash command could rewrite it; Claude Code reads hooks at session start, so the change would
not take effect in the running session, and each container starts from the image. Claude Code's managed
settings (`/etc/claude-code/managed-settings.json`, root-owned, not overridable by user settings) would close
this for long-lived containers. Deferred until a container runs more than one session.
