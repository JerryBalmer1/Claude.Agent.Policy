BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $ModuleRoot 'Claude.Agent.Policy.psd1')

    function Get-SkillVersion([string] $Name) {
        $skill = Get-Content -LiteralPath (Join-Path $RepoRoot '.claude' 'skills' $Name 'SKILL.md') -Raw
        $front = [regex]::Match($skill, '\A---\r?\n(.*?)\r?\n---', 'Singleline').Groups[1].Value
        [regex]::Match($front, '(?m)^version:\s*(\S+)\s*$').Groups[1].Value
    }
}

Describe 'Module' {
    It 'is version 0.1.0 and needs PowerShell 7.4' {
        $Manifest.ModuleVersion | Should -Be '0.1.0'
        $Manifest.PowerShellVersion | Should -Be '7.4'
    }

    It 'exports exactly the functions the manifest lists, one Public file each' {
        @((Get-Module Claude.Agent.Policy).ExportedFunctions.Keys | Sort-Object) | Should -Be @($Manifest.FunctionsToExport | Sort-Object)
        @(Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter '*.ps1' | ForEach-Object BaseName | Sort-Object) | Should -Be @($Manifest.FunctionsToExport | Sort-Object)
    }

    It 'ships its defaults and tool ontology inside the module directory' {
        Join-Path $ModuleRoot 'policy.defaults.json' | Should -Exist
        Join-Path $ModuleRoot 'ontology/claude-code.yaml' | Should -Exist
    }
}

Describe 'FileSystem ontology fixture' {
    It 'matches Graph.Emitter.FileSystem/ontology.yaml in the sibling checkout' {
        $sibling = Join-Path (Split-Path -Parent $RepoRoot) 'Graph.Emitter.FileSystem/ontology.yaml'
        if (-not (Test-Path -LiteralPath $sibling)) {
            Set-ItResult -Skipped -Because "Graph.Emitter.FileSystem is not checked out at $sibling"
            return
        }
        (Get-Content -LiteralPath $FileSystemOntology -Raw) -replace "`r`n", "`n" | Should -Be ((Get-Content -LiteralPath $sibling -Raw) -replace "`r`n", "`n") -Because 'the fixture is a copy; recopy it when the emitter''s ontology changes'
    }
}

Describe 'repo skills' {
    It 'readme front-matter version equals this module''s ModuleVersion' {
        Get-SkillVersion 'readme' | Should -Be $Manifest.ModuleVersion -Because 'bump the skill with the module'
    }

    It 'tool-map front-matter version equals this module''s ModuleVersion' {
        Get-SkillVersion 'tool-map' | Should -Be $Manifest.ModuleVersion -Because 'bump the skill with the module'
    }

    It 'ledger-writer (copied from Claude.Agent.Ledger) front-matter version equals Claude.Agent.Ledger''s ModuleVersion' {
        $ledgerManifest = Join-Path $LedgerSrc 'Claude.Agent.Ledger/Claude.Agent.Ledger.psd1'
        if (-not (Test-Path -LiteralPath $ledgerManifest)) {
            Set-ItResult -Skipped -Because "Claude.Agent.Ledger is not checked out at $ledgerManifest"
            return
        }
        Get-SkillVersion 'ledger-writer' | Should -Be (Import-PowerShellDataFile -Path $ledgerManifest).ModuleVersion -Because 'recopy .claude/skills/ledger-writer from Claude.Agent.Ledger''s README when its version changes'
    }
}
