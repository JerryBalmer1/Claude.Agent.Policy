BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'New-Policy' {
    BeforeAll {
        $out = Join-Path $TestDrive 'policy.json'
        $policy = New-Policy -OntologyPath $FileSystemOntology -OutPath $out
        $byName = @{}
        foreach ($r in $policy.rules) { $byName["$($r.kind).$($r.action)"] = $r }
    }

    It 'a policy generated from the FileSystem ontology validates' {
        Test-Policy -Path $out -OntologyPath $FileSystemOntology | Should -BeTrue
        $out | Should -Exist
        $policy.version | Should -Be 1
        $policy.default | Should -Be 'deny'
        $policy.generated | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }

    It 'has one rule per declared Kind.action, sorted, each set from the defaults' {
        @($policy.rules | ForEach-Object { "$($_.kind).$($_.action)=$($_.effect)" }) | Should -Be @(
            'Directory.delete=deny', 'Directory.read=allow', 'File.delete=deny', 'File.read=allow', 'File.write=allow', 'Shell.exec=witness')
        @($byName['File.write'].paths) | Should -Be @('/work/**')
    }

    It 'throws when a declared action has no default' {
        $onto = Join-Path $TestDrive 'extra.yaml'
        Set-Content -LiteralPath $onto -Value "module: X`nkinds:`n  File:`n    actions:`n      - name: chmod`n        inputs: { id: string }`n"
        { New-Policy -OntologyPath $onto } | Should -Throw -ExpectedMessage '*No default*File.chmod*'
    }

    It 'reads block items whose name is not the first key, and ignores nested name keys' {
        $onto = Join-Path $TestDrive 'shapes.yaml'
        Set-Content -LiteralPath $onto -Value @"
module: X
kinds:
  Volume:
    description: test  # a comment
    actions:
      - description: first
        name: delete
        inputs:
          name: string
      - { name: read, trigger: manual }
  Empty:
    actions: []
edgeKinds:
  contains:
    actions:
      - name: ignored
"@
        $p = New-Policy -OntologyPath $onto
        @($p.rules | Where-Object kind -eq 'Volume' | ForEach-Object action) | Should -Be @('delete', 'read')
        @($p.rules | Where-Object action -eq 'ignored') | Should -HaveCount 0
    }

    It 'ignores list items nested in an action (inputs as a list, as Graph.Emitter.FileSystem 0.1.2 writes them)' {
        $onto = Join-Path $TestDrive 'inputs-list.yaml'
        Set-Content -LiteralPath $onto -Value @"
module: X
kinds:
  File:
    actions:
      - name: delete
        inputs:
          - { name: id, type: File, required: true }
          - name: force
            type: boolean
        returns: { type: File }
      - name: read
"@
        $p = New-Policy -OntologyPath $onto
        $actions = @($p.rules | Where-Object kind -eq 'File' | ForEach-Object action)
        $actions | Should -Contain 'delete'
        $actions | Should -Contain 'read'
        $actions | Should -Not -Contain 'id'
        $actions | Should -Not -Contain 'force'
    }
}

Describe 'Test-Policy' {
    BeforeAll {
        $base = [ordered]@{ version = 1; generated = '2026-10-08T00:00:00Z'; default = 'deny' }
    }

    It 'fails a rule for an undeclared Kind.action' {
        $p = $base + @{ rules = @([ordered]@{ kind = 'File'; action = 'chmod'; effect = 'allow' }) }
        { Test-Policy -Policy $p -OntologyPath $FileSystemOntology } | Should -Throw -ExpectedMessage '*rules`[0`]: File.chmod is not declared*'
    }

    It 'fails File.delete when only the tool ontology is in play' {
        $empty = Join-Path $TestDrive 'empty.yaml'
        Set-Content -LiteralPath $empty -Value "module: X`nkinds:`n  Thing:`n    description: none`n"
        $p = $base + @{ rules = @([ordered]@{ kind = 'File'; action = 'delete'; effect = 'deny' }) }
        { Test-Policy -Policy $p -OntologyPath $empty } | Should -Throw -ExpectedMessage '*File.delete is not declared*'
    }

    It 'fails the schema: unknown effect, relative path glob, default other than deny' {
        $p = [ordered]@{ version = 1; generated = '2026-10-08T00:00:00Z'; default = 'allow'; rules = @(
            [ordered]@{ kind = 'File'; action = 'read'; effect = 'maybe' },
            [ordered]@{ kind = 'File'; action = 'write'; effect = 'allow'; paths = @('work/**') }) }
        { Test-Policy -Policy $p -OntologyPath $FileSystemOntology } | Should -Throw -ExpectedMessage '*schema:*'
    }
}

Describe 'Resolve-PolicyDecision' {
    BeforeAll {
        $policy = New-Policy -OntologyPath $FileSystemOntology
        function Get-Decision([string] $Tool, [hashtable] $In) { Resolve-PolicyDecision -Tool $Tool -Input $In -Cwd '/work' -Policy $policy }
    }

    It 'maps <tool> to <kindAction> and decides <effect>' -ForEach @(
        @{ tool = 'Read'; in = @{ file_path = '/etc/hostname' }; kindAction = 'File.read'; effect = 'allow' }
        @{ tool = 'Write'; in = @{ file_path = '/work/a.txt' }; kindAction = 'File.write'; effect = 'allow' }
        @{ tool = 'Edit'; in = @{ file_path = 'sub/a.txt' }; kindAction = 'File.write'; effect = 'allow' }
        @{ tool = 'Write'; in = @{ file_path = '/etc/passwd' }; kindAction = 'File.write'; effect = 'deny' }
        @{ tool = 'Write'; in = @{ file_path = '/work/../etc/passwd' }; kindAction = 'File.write'; effect = 'deny' }
        @{ tool = 'Write'; in = @{ file_path = '/workshop/a' }; kindAction = 'File.write'; effect = 'deny' }
        @{ tool = 'Glob'; in = @{ pattern = '*.md' }; kindAction = 'Directory.read'; effect = 'allow' }
        @{ tool = 'Grep'; in = @{ pattern = 'x'; path = '/usr' }; kindAction = 'Directory.read'; effect = 'allow' }
        @{ tool = 'Bash'; in = @{ command = 'ls -la' }; kindAction = 'Shell.exec'; effect = 'witness' }
    ) {
        $d = Get-Decision $tool $in
        $d.kindAction | Should -Be $kindAction
        $d.effect | Should -Be $effect
        $d.rule | Should -Match '^(rules\[\d+\]|default)$'
        $d.reason | Should -Not -BeNullOrEmpty
    }

    It 'names the rule and normalises the path' {
        $d = Get-Decision 'Write' @{ file_path = 'sub/./x/../a.txt' }
        $d.path | Should -Be '/work/sub/a.txt'
        $d.rule | Should -Be "rules[$([array]::IndexOf(@($policy.rules.action), 'write'))]"
        $d = Get-Decision 'Write' @{ file_path = '/etc/passwd' }
        $d.rule | Should -Be 'default'
        $d.reason | Should -BeLike '*matches no rule for File.write*default is deny*'
    }

    It 'classifies a Bash delete as File.delete or Directory.delete and denies it' {
        $d = Get-Decision 'Bash' @{ command = "rm -f /work/a.txt" }
        $d.kindAction, $d.effect, $d.path | Should -Be @('File.delete', 'deny', '/work/a.txt')
        $d = Get-Decision 'Bash' @{ command = "cd /work && rm -r -f 'some dir'" }
        $d.kindAction, $d.effect, $d.path | Should -Be @('Directory.delete', 'deny', '/work/some dir')
        (Get-Decision 'Bash' @{ command = 'unlink /work/a' }).kindAction | Should -Be 'File.delete'
        (Get-Decision 'Bash' @{ command = 'rmdir /work/d' }).kindAction | Should -Be 'Directory.delete'
        (Get-Decision 'Bash' @{ command = "FOO=1 sudo -n /bin/rm -- -x" }).path | Should -Be '/work/-x'
        (Get-Decision 'Bash' @{ command = 'find /tmp -name "*.o" -delete' }).path | Should -Be '/tmp'
        (Get-Decision 'Bash' @{ command = "ls | xargs rm" }).effect | Should -Be 'deny'
        (Get-Decision 'Bash' @{ command = "echo 'rm -f x'" }).kindAction | Should -Be 'Shell.exec'
    }

    It 'gives a tool with no Kind.action the policy default' {
        $d = Get-Decision 'WebFetch' @{ url = 'https://example.com' }
        $d.effect | Should -Be 'deny'
        $d.kindAction | Should -BeNullOrEmpty
        $d.reason | Should -BeLike '*maps to no Kind.action*'
    }

    It 'accepts the tool input as JSON text and the policy as a path' {
        $path = Join-Path $TestDrive 'p.json'
        New-Policy -OntologyPath $FileSystemOntology -OutPath $path | Out-Null
        (Resolve-PolicyDecision -Tool 'Write' -Input '{"file_path":"/work/j.txt"}' -Cwd '/work' -Policy $path).effect | Should -Be 'allow'
    }
}
