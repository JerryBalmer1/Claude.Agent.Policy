#Requires -Version 7.4
# Claude Code PostToolUse hook (matcher: all tools). The call has run; spool one policy.<effect> entry (phase
# post) with the same decision the pre hook made, so every call that ran has a matching pair in the ledger.
# A post entry whose effect is deny means a call ran that the policy refuses (nothing should produce one).
# Always exits 0: the call already happened and there is nothing left to block. Failures go to stderr.
# Policy: $env:CLAUDE_AGENT_POLICY, else policy.json one directory up. Spool: $env:CLAUDE_AGENT_SPOOL, else /spool.
$ErrorActionPreference = 'Stop'
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    if ($payload -isnot [System.Collections.IDictionary] -or -not $payload['tool_name']) { throw 'hook payload has no tool_name' }
    Import-Module Claude.Agent.Policy, Claude.Agent.Ledger

    $policy = if ($env:CLAUDE_AGENT_POLICY) { $env:CLAUDE_AGENT_POLICY } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.json' }
    $spool = if ($env:CLAUDE_AGENT_SPOOL) { $env:CLAUDE_AGENT_SPOOL } else { '/spool' }
    $decision = Resolve-PolicyDecision -Tool $payload.tool_name -Input $payload['tool_input'] -Cwd $payload['cwd'] -Policy $policy

    $body = @{ phase = 'post'; tool = $decision.tool; kindAction = $decision.kindAction; path = $decision.path; rule = $decision.rule }
    if ($null -ne $decision.command) { $body.command = $decision.command }
    Add-LedgerEntry -Spool $spool -Kind "policy.$($decision.effect)" -Body $body | Out-Null
}
catch {
    [Console]::Error.WriteLine("Claude.Agent policy: post-tool-use record failed: $($_.Exception.Message)")
}
exit 0
