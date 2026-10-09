#Requires -Version 7.4
# Claude Code PreToolUse hook (matcher: all tools). Reads the hook payload from stdin, decides the call with
# Resolve-PolicyDecision and spools one policy.<effect> entry (phase pre) before answering:
#   allow / witness  exit 0, stdout {"hookSpecificOutput": {permissionDecision: allow}}: the policy is the
#                    permission authority, so Claude Code does not ask (design.md 4);
#   deny             exit 2, the reason on stderr; Claude Code blocks the call and shows the model the reason.
# Fails closed: any error (no policy, unreadable payload, the spool write failing) is a deny with exit 2,
# because only exit 2 blocks; any other non-zero exit lets the call through.
# Policy: $env:CLAUDE_AGENT_POLICY, else policy.json one directory up. Spool: $env:CLAUDE_AGENT_SPOOL, else /spool.
$ErrorActionPreference = 'Stop'
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    if ($payload -isnot [System.Collections.IDictionary] -or -not $payload['tool_name']) { throw 'hook payload has no tool_name' }
    Import-Module Claude.Agent.Policy, Claude.Agent.Ledger

    $policy = if ($env:CLAUDE_AGENT_POLICY) { $env:CLAUDE_AGENT_POLICY } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.json' }
    $spool = if ($env:CLAUDE_AGENT_SPOOL) { $env:CLAUDE_AGENT_SPOOL } else { '/spool' }
    $decision = Resolve-PolicyDecision -Tool $payload.tool_name -Input $payload['tool_input'] -Cwd $payload['cwd'] -Policy $policy

    $body = @{ phase = 'pre'; tool = $decision.tool; kindAction = $decision.kindAction; path = $decision.path; rule = $decision.rule; reason = $decision.reason }
    if ($null -ne $decision.command) { $body.command = $decision.command }
    Add-LedgerEntry -Spool $spool -Kind "policy.$($decision.effect)" -Body $body | Out-Null
}
catch {
    [Console]::Error.WriteLine("Claude.Agent policy: denied, the policy hook failed: $($_.Exception.Message)")
    exit 2
}

if ($decision.effect -eq 'deny') {
    [Console]::Error.WriteLine("Claude.Agent policy: $($decision.reason).")
    exit 2
}
@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'allow'
        permissionDecisionReason = "Claude.Agent policy: $($decision.reason)"
    }
} | ConvertTo-Json -Compress -Depth 4
exit 0
