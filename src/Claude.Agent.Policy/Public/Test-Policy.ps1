function Test-Policy {
    <#
    .SYNOPSIS
    Checks a policy against schemas/policy.schema.json and against the ontologies. Returns $true or throws.
    .DESCRIPTION
    Two checks, and every problem from both is listed in the error:
    - the JSON satisfies policy.schema.json;
    - every rule's Kind.action is declared by one of -OntologyPath or by this module's ontology/claude-code.yaml.
    -Policy is a path to policy.json or the object New-Policy returned.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][Alias('Path')][object] $Policy,
        [Parameter(Mandatory)][string[]] $OntologyPath,
        [string] $SchemaPath
    )

    $ErrorActionPreference = 'Stop'
    if (-not $SchemaPath) { $SchemaPath = Find-PolicySchema }
    $read = Read-PolicyDocument -Policy $Policy
    $problems = [System.Collections.Generic.List[string]]::new()

    $schemaErrors = $null
    $valid = Test-Json -Json $read.Json -SchemaFile $SchemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
    if (-not $valid) {
        foreach ($e in @($schemaErrors)) { $problems.Add("schema: $($e.Exception.Message)") }
        if (-not $problems.Count) { $problems.Add('schema: invalid') }
    }

    $declared = Get-DeclaredAction -OntologyPath $OntologyPath
    $rules = @(if ($read.Document -is [System.Collections.IDictionary] -and $read.Document.ContainsKey('rules')) { $read.Document.rules })
    for ($n = 0; $n -lt $rules.Count; $n++) {
        $r = $rules[$n]
        if ($r -isnot [System.Collections.IDictionary]) { continue }
        $kindAction = "$($r['kind']).$($r['action'])"
        if ($declared -cnotcontains $kindAction) { $problems.Add("rules[$n]: $kindAction is not declared by any ontology") }
    }

    if ($problems.Count) {
        $name = if ($Policy -is [string]) { "'$Policy'" } else { '(object)' }
        throw "Policy $name failed: $($problems -join '; ')"
    }
    $true
}
