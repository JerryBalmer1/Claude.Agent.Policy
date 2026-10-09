function Resolve-PolicyDecision {
    <#
    .SYNOPSIS
    Decides one Claude Code tool call: returns {effect, rule, reason} plus the tool, kindAction, path and targets.
    .DESCRIPTION
    The tool maps to a Kind.action (design.md 1); a Bash command that deletes maps to File.delete or
    Directory.delete per target, anything else to Shell.exec. Each target is decided by the first matching rule
    or the policy default, and the strictest decision (deny, then witness, then allow) is the call's decision.
    A tool with no mapping gets the policy default.

    -Input is the tool_input object from the hook payload (hashtable, object or JSON text). Relative paths are
    taken against -Cwd. -Policy is a path or the object New-Policy returned; it defaults to $env:CLAUDE_AGENT_POLICY,
    else /opt/agent/policy/policy.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Tool,
        [Alias('Input')][AllowNull()][object] $ToolInput,
        [string] $Cwd,
        [object] $Policy
    )

    $ErrorActionPreference = 'Stop'
    if (-not $Policy) { $Policy = if ($env:CLAUDE_AGENT_POLICY) { $env:CLAUDE_AGENT_POLICY } else { $script:DefaultPolicyPath } }
    if (-not $Cwd) { $Cwd = if ($PWD.Path.StartsWith('/')) { $PWD.Path } else { '/' } }
    $doc = (Read-PolicyDocument -Policy $Policy).Document
    $in = ConvertTo-Hashtable -InputObject $ToolInput

    $command = $null
    if (-not $script:ToolMap.ContainsKey($Tool)) {
        $targets = @([pscustomobject]@{ KindAction = $null; Path = $null })
    }
    elseif ($Tool -eq 'Bash') {
        $command = if ($in.ContainsKey('command')) { [string]$in.command } else { '' }
        $targets = Get-ShellTarget -Command $command -Cwd $Cwd
    }
    else {
        $map = $script:ToolMap[$Tool]
        $raw = if ($in.ContainsKey($map.PathMember)) { [string]$in[$map.PathMember] } else { $null }
        # Glob, Grep and LS without a path search the working directory.
        if (-not $raw -and $map.KindAction -eq 'Directory.read') { $raw = $Cwd }
        $targets = @([pscustomobject]@{ KindAction = $map.KindAction; Path = (ConvertTo-PolicyPath -Path $raw -Cwd $Cwd) })
    }

    $decisions = foreach ($t in $targets) {
        if (-not $t.KindAction) {
            [pscustomobject]@{ effect = $doc.default; rule = 'default'; reason = "tool $Tool maps to no Kind.action; policy default is $($doc.default)"; kindAction = $null; path = $null }
        }
        else {
            Resolve-PolicyTarget -Document $doc -KindAction $t.KindAction -Path $t.Path
        }
    }
    $decisions = @($decisions)
    $decisive = $decisions[0]
    foreach ($d in $decisions) { if ($script:EffectRank[$d.effect] -gt $script:EffectRank[$decisive.effect]) { $decisive = $d } }

    [pscustomobject]@{
        effect     = $decisive.effect
        rule       = $decisive.rule
        reason     = $decisive.reason
        tool       = $Tool
        kindAction = $decisive.kindAction
        path       = $decisive.path
        command    = $command
        targets    = $decisions
    }
}
