---
name: tool-map
description: Keep the Claude Code tool -> Kind.action map in step across design.md 1, the $script:ToolMap and Get-ShellTarget in Private/PolicyCore.ps1, ontology/claude-code.yaml, policy.defaults.json and the tests. Use whenever a Claude Code tool is added, renamed or remapped, the Bash delete classifier changes, an emitter ontology gains an action, or a default effect changes.
version: 0.1.0
---

# Tool map

A Claude Code tool call becomes one or more `Kind.action` targets, and the policy decides each. The map lives
in five places that must agree:

| Place | What it holds |
| --- | --- |
| `docs/design.md` entry 1 | The map as a table, and why. The source of truth for humans. |
| `src/Claude.Agent.Policy/Private/PolicyCore.ps1` `$script:ToolMap` | Tool -> Kind.action and the `tool_input` member that names the path. |
| `Private/PolicyCore.ps1` `Get-ShellTarget` | Which Bash commands are deletes (File.delete / Directory.delete); the rest is Shell.exec. |
| `src/Claude.Agent.Policy/ontology/claude-code.yaml` | Declares every Kind.action the map produces that no emitter ontology declares. |
| `src/Claude.Agent.Policy/policy.defaults.json` | The effect (and paths) for every declared action, by Kind.action, else by action. |

## When to update

In the same task as any change to one of the five. Pester (`tests/Policy.Tests.ps1`, Resolve-PolicyDecision)
has a row per mapped tool; add or change the row with the map.

## Rules

- Every Kind.action the map can produce is declared by an ontology. If an emitter (e.g. Graph.Emitter.FileSystem)
  declares it, do not redeclare it in `claude-code.yaml`; if none does, declare it there with a description.
- Every declared Kind.action has a default. New-Policy throws when one is missing; fix the defaults, never
  catch the throw.
- A tool with no entry gets the policy default (deny). Mapping a new tool is a decision: add it to design.md 1.
- The Bash classifier is lexical and best-effort (design.md 2). Widen it only with a test per new pattern, and
  never let a parse failure turn a delete into Shell.exec silently; prefer over-classifying as a delete.
- `version` above equals the module's `ModuleVersion` (Pester checks). Bump both together.
