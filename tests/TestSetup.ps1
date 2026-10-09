# Dot-sourced by each test file's BeforeAll.
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'src/Claude.Agent.Policy'
$LedgerSrc = Join-Path (Split-Path -Parent $RepoRoot) 'Claude.Agent.Ledger/src'
$FileSystemOntology = Join-Path $PSScriptRoot 'fixtures/Graph.Emitter.FileSystem.ontology.yaml'
Import-Module (Join-Path $ModuleRoot 'Claude.Agent.Policy.psd1') -Force

# Runs a hook script in a clean pwsh with the payload on stdin; both sibling modules resolve by name.
function Invoke-Hook {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][hashtable] $Payload,
        [Parameter(Mandatory)][string] $Policy,
        [Parameter(Mandatory)][string] $Spool
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
    foreach ($a in '-NoProfile', '-NonInteractive', '-File', (Join-Path $RepoRoot "hooks/$Name.ps1")) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['PSModulePath'] = ((Join-Path $RepoRoot 'src'), $LedgerSrc, $env:PSModulePath) -join [System.IO.Path]::PathSeparator
    $psi.Environment['CLAUDE_AGENT_POLICY'] = $Policy
    $psi.Environment['CLAUDE_AGENT_SPOOL'] = $Spool

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write(($Payload | ConvertTo-Json -Depth 8 -Compress))
    $p.StandardInput.Close()
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout.Result.Trim(); Stderr = $stderr.Result.Trim() }
}

function New-HookPayload {
    param([string] $Event = 'PreToolUse', [string] $Tool, [hashtable] $ToolInput)
    @{
        session_id      = 'test'
        transcript_path = '/tmp/transcript.jsonl'
        cwd             = '/work'
        hook_event_name = $Event
        tool_name       = $Tool
        tool_input      = $ToolInput
    }
}
