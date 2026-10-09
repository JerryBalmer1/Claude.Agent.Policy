BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    if (-not (Test-Path -LiteralPath (Join-Path $LedgerSrc 'Claude.Agent.Ledger/Claude.Agent.Ledger.psd1'))) {
        throw "The hooks need Claude.Agent.Ledger checked out next to this repo ($LedgerSrc)."
    }
    $policyPath = Join-Path $TestDrive 'policy.json'
    New-Policy -OntologyPath $FileSystemOntology -OutPath $policyPath | Out-Null

    # Each call gets its own spool, so each test sees only the entries it caused.
    function Invoke-PreHook([string] $Tool, [hashtable] $In) {
        $spool = Join-Path $TestDrive "spool-$([guid]::NewGuid())"
        $r = Invoke-Hook -Name 'pre-tool-use' -Payload (New-HookPayload -Tool $Tool -ToolInput $In) -Policy $policyPath -Spool $spool
        $r | Add-Member -NotePropertyName Entries -NotePropertyValue @(Get-SpoolEntry $spool) -PassThru
    }
    function Get-SpoolEntry([string] $Spool) {
        $file = Join-Path $Spool 'pending.jsonl'
        if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file | ConvertFrom-Json }
    }
}

Describe 'pre-tool-use hook' {
    It 'denies File.delete (Bash rm) with exit 2 and the reason on stderr' {
        $r = Invoke-PreHook 'Bash' @{ command = 'rm /work/out.txt' }
        $r.ExitCode | Should -Be 2
        $r.Stderr | Should -BeLike '*File.delete /work/out.txt denied by policy rules`[*`]*'
        $r.Stdout | Should -BeNullOrEmpty
    }

    It 'allows File.write under /work with exit 0 and a permissionDecision of allow' {
        $r = Invoke-PreHook 'Write' @{ file_path = '/work/out.txt'; content = 'x' }
        $r.ExitCode | Should -Be 0
        $out = $r.Stdout | ConvertFrom-Json
        $out.hookSpecificOutput.hookEventName | Should -Be 'PreToolUse'
        $out.hookSpecificOutput.permissionDecision | Should -Be 'allow'
    }

    It 'denies File.write outside /work with exit 2' {
        $r = Invoke-PreHook 'Write' @{ file_path = '/etc/cron.d/x'; content = 'x' }
        $r.ExitCode | Should -Be 2
        $r.Stderr | Should -BeLike '*File.write /etc/cron.d/x matches no rule*'
    }

    It 'allows Shell.exec as a witness' {
        $r = Invoke-PreHook 'Bash' @{ command = 'ls -la' }
        $r.ExitCode | Should -Be 0
        ($r.Stdout | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should -Be 'allow'
    }

    It 'spools one entry per decision with the right kind and fields' -ForEach @(
        @{ tool = 'Read'; in = @{ file_path = '/etc/hostname' }; kind = 'policy.allow'; kindAction = 'File.read'; path = '/etc/hostname' }
        @{ tool = 'Write'; in = @{ file_path = '/work/out.txt' }; kind = 'policy.allow'; kindAction = 'File.write'; path = '/work/out.txt' }
        @{ tool = 'Write'; in = @{ file_path = '/etc/x' }; kind = 'policy.deny'; kindAction = 'File.write'; path = '/etc/x' }
        @{ tool = 'Bash'; in = @{ command = 'rm /work/out.txt' }; kind = 'policy.deny'; kindAction = 'File.delete'; path = '/work/out.txt' }
        @{ tool = 'Bash'; in = @{ command = 'ls -la' }; kind = 'policy.witness'; kindAction = 'Shell.exec'; path = $null }
    ) {
        $r = Invoke-PreHook $tool $in
        $r.Entries | Should -HaveCount 1
        $e = $r.Entries[0]
        $e.kind | Should -Be $kind
        $e.body.phase | Should -Be 'pre'
        $e.body.tool | Should -Be $tool
        $e.body.kindAction | Should -Be $kindAction
        $e.body.path | Should -Be $path
        $e.body.rule | Should -Match '^(rules\[\d+\]|default)$'
        if ($tool -eq 'Bash') { $e.body.command | Should -Be $in.command }
    }

    It 'fails closed: no policy file means exit 2 and nothing spooled' {
        $spool = Join-Path $TestDrive 'spool-nopolicy'
        $r = Invoke-Hook -Name 'pre-tool-use' -Payload (New-HookPayload -Tool 'Read' -ToolInput @{ file_path = '/etc/hostname' }) -Policy (Join-Path $TestDrive 'missing.json') -Spool $spool
        $r.ExitCode | Should -Be 2
        $r.Stderr | Should -BeLike '*policy hook failed*'
        @(Get-SpoolEntry $spool) | Should -HaveCount 0
    }
}

Describe 'post-tool-use hook' {
    It 'spools a phase post entry with the same decision and exits 0' {
        $spool = Join-Path $TestDrive 'spool-post'
        $payload = New-HookPayload -Event 'PostToolUse' -Tool 'Write' -ToolInput @{ file_path = '/work/out.txt' }
        $payload.tool_response = @{ filePath = '/work/out.txt'; success = $true }
        $r = Invoke-Hook -Name 'post-tool-use' -Payload $payload -Policy $policyPath -Spool $spool
        $r.ExitCode | Should -Be 0
        $e = @(Get-SpoolEntry $spool)
        $e | Should -HaveCount 1
        $e[0].kind | Should -Be 'policy.allow'
        $e[0].body.phase | Should -Be 'post'
        $e[0].body.kindAction | Should -Be 'File.write'
    }
}

Describe 'hooks/settings.json' {
    It 'wires PreToolUse and PostToolUse for all tools to the two hooks under /opt/agent/policy/hooks' {
        $settings = Get-Content (Join-Path $RepoRoot 'hooks/settings.json') -Raw | ConvertFrom-Json
        foreach ($pair in @(@('PreToolUse', 'pre-tool-use.ps1'), @('PostToolUse', 'post-tool-use.ps1'))) {
            $groups = @($settings.hooks.($pair[0]))
            $groups | Should -HaveCount 1
            $groups[0].matcher | Should -Be '*'
            $groups[0].hooks[0].type | Should -Be 'command'
            $groups[0].hooks[0].command | Should -BeLike "pwsh *-File /opt/agent/policy/hooks/$($pair[1])"
            Join-Path $RepoRoot "hooks/$($pair[1])" | Should -Exist
        }
    }
}
