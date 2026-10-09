function New-Policy {
    <#
    .SYNOPSIS
    Writes a policy with one rule for every Kind.action the given ontologies declare, each set from the defaults.
    .DESCRIPTION
    Reads the actions blocks of each -OntologyPath (kinds.<Kind>.actions[].name) plus this module's own
    ontology/claude-code.yaml (the actions Claude Code's tools map to, design.md 1). For every declared
    Kind.action the defaults file supplies the effect, and paths if any: byKindAction first, then byAction.
    A declared action with no default is an error, so a new action in an ontology never ships unconsidered.

    Rules are sorted by Kind then action. The result is checked with Test-Policy, written to -OutPath if given,
    and returned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $OntologyPath,
        [string] $DefaultsPath = $script:DefaultsPath,
        [string] $OutPath,
        [string] $SchemaPath
    )

    $ErrorActionPreference = 'Stop'
    $DefaultsPath = Get-FullPath -Path $DefaultsPath
    if ($OutPath) { $OutPath = Get-FullPath -Path $OutPath }
    if (-not (Test-Path -LiteralPath $DefaultsPath -PathType Leaf)) { throw "Policy defaults not found at '$DefaultsPath'." }
    $defaults = [System.IO.File]::ReadAllText($DefaultsPath) | ConvertFrom-Json -AsHashtable
    $byAction = if ($defaults.ContainsKey('byAction')) { $defaults.byAction } else { @{} }
    $byKindAction = if ($defaults.ContainsKey('byKindAction')) { $defaults.byKindAction } else { @{} }

    $missing = [System.Collections.Generic.List[string]]::new()
    $rules = foreach ($kindAction in (Get-DeclaredAction -OntologyPath $OntologyPath)) {
        $kind, $action = $kindAction.Split('.', 2)
        $choice = if ($byKindAction.ContainsKey($kindAction)) { $byKindAction[$kindAction] }
                  elseif ($byAction.ContainsKey($action)) { $byAction[$action] }
                  else { $null }
        if (-not $choice) { $missing.Add($kindAction); continue }
        $rule = [ordered]@{ kind = $kind; action = $action; effect = $choice.effect }
        if ($choice.ContainsKey('paths')) { $rule.paths = @($choice.paths) }
        $rule
    }
    if ($missing.Count) {
        throw "No default in '$DefaultsPath' for declared action(s): $($missing -join ', '). Add them under byKindAction or byAction."
    }

    $policy = [ordered]@{
        version   = $script:PolicyFormatVersion
        generated = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        default   = $defaults.default
        rules     = @($rules)
    }

    $testArgs = @{ Policy = $policy; OntologyPath = $OntologyPath }
    if ($SchemaPath) { $testArgs.SchemaPath = $SchemaPath }
    Test-Policy @testArgs | Out-Null

    if ($OutPath) {
        $dir = Split-Path -Parent $OutPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($OutPath, ($policy | ConvertTo-Json -Depth 16) + "`n", [System.Text.UTF8Encoding]::new($false))
    }
    [pscustomobject]$policy
}
