@{
    RootModule           = 'Claude.Agent.Policy.psm1'
    ModuleVersion        = '0.1.1'
    GUID                 = 'b8e4a2d1-5c3f-4e7a-9d6b-1a0f3c8e7b24'
    Author               = 'JerryBalmer1'
    Description          = 'Tool policy for Claude.Agent: generated from emitter ontologies, enforced by Claude Code hooks, every decision ledgered.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('New-Policy', 'Test-Policy', 'Resolve-PolicyDecision')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ Tags = @('policy', 'hooks', 'claude-code') } }
}
