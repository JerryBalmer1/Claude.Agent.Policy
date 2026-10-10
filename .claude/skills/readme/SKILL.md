---
name: readme
description: Keep README.md, the usage door to Claude.Agent.Policy, in step with the code. Use whenever an exported function or its parameters change, the policy shape or schema changes, a hook's inputs, outputs, exit codes or ledger fields change, hooks/settings.json changes, an Invoke-Build task or requirement changes, or the version changes, and before reporting any task that touched one.
version: 0.1.2
---

# README

`README.md` is for whoever bakes the policy into an image, reads a policy decision in the ledger, or changes
what the agent may do. The decisions behind it live in `docs/design.md`; README links them, never repeats them.

## When to update it

In the same task as any change to:
- an exported function (psd1 `FunctionsToExport`, `src/Claude.Agent.Policy/Public/`) or its parameters
- `schemas/policy.schema.json`, `policy.defaults.json`, or `ontology/claude-code.yaml`
- `hooks/pre-tool-use.ps1` / `hooks/post-tool-use.ps1`: exit codes, stdout, environment variables, ledger kinds or body fields
- `hooks/settings.json`, or the `/opt/agent/policy` layout Claude.Agent bakes
- `.build.ps1` tasks, the PowerShell or Pester minimums, or the sibling repos the tests need
- the psd1 version

## Rules

- Sections stay in this order: what it is (under the title), Policy, Functions, Hooks, How Claude.Agent bakes it in, Development.
- The Functions table lists exactly the psd1 `FunctionsToExport`, in that order, with exact parameter names.
- The Hooks section states each hook's exit codes and the ledger body fields exactly as the scripts write them.
- Examples are ones you ran. Use exact command and parameter names; an output comment is what you saw.
- Dense, plain sentences. No marketing words. A table beats a paragraph.
- `version` above equals the module's `ModuleVersion` (Pester checks). Bump both together.
