# Shared helpers for the policy. Not exported.

$script:ModuleRoot       = Split-Path -Parent $PSScriptRoot
$script:ToolOntologyPath = Join-Path $script:ModuleRoot 'ontology/claude-code.yaml'
$script:DefaultsPath     = Join-Path $script:ModuleRoot 'policy.defaults.json'
$script:DefaultPolicyPath = '/opt/agent/policy/policy.json'
$script:PolicyFormatVersion = 1
$script:EffectRank       = @{ allow = 0; witness = 1; deny = 2 }

# Claude Code tool -> Kind.action, and the tool_input member that names the target (design.md 1).
# Bash is classified per command by Get-ShellTarget: a delete is File.delete / Directory.delete, anything else Shell.exec.
$script:ToolMap = @{
    Read         = @{ KindAction = 'File.read';      PathMember = 'file_path' }
    Edit         = @{ KindAction = 'File.write';     PathMember = 'file_path' }
    MultiEdit    = @{ KindAction = 'File.write';     PathMember = 'file_path' }
    Write        = @{ KindAction = 'File.write';     PathMember = 'file_path' }
    NotebookEdit = @{ KindAction = 'File.write';     PathMember = 'notebook_path' }
    Glob         = @{ KindAction = 'Directory.read'; PathMember = 'path' }
    Grep         = @{ KindAction = 'Directory.read'; PathMember = 'path' }
    LS           = @{ KindAction = 'Directory.read'; PathMember = 'path' }
    Bash         = @{ KindAction = 'Shell.exec';     PathMember = $null }
}

# Reads the Kind.action pairs an emitter ontology declares under kinds.<Kind>.actions[].name.
# A narrow, indentation-based reader for that one path, so the module stays dependency-free inside the image;
# Graph.Node's validate-ontology owns full validation of the file.
function Read-OntologyAction {
    param([Parameter(Mandatory)][string] $Path)

    $Path = Get-FullPath -Path $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Ontology not found at '$Path'." }
    $found = [System.Collections.Generic.List[string]]::new()
    $inKinds = $false; $kindIndent = -1; $kind = $null
    $actionsIndent = -1; $itemIndent = -1; $itemKeyIndent = -1

    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $line = [regex]::Replace($raw, '(^|\s)#.*$', '')
        if ($line.Trim().Length -eq 0) { continue }
        $indent = $line.Length - $line.TrimStart(' ').Length
        $text = $line.Trim()

        if ($indent -eq 0) {
            $inKinds = $text -match '^kinds:\s*$'
            $kindIndent = -1; $kind = $null; $actionsIndent = -1
            continue
        }
        if (-not $inKinds) { continue }

        if ($kindIndent -lt 0) { $kindIndent = $indent }
        if ($indent -eq $kindIndent) {
            if ($text -notmatch '^([A-Za-z][\w-]*):\s*$') { throw "Ontology '$Path': expected a Kind name under kinds, got '$text'." }
            $kind = $Matches[1]; $actionsIndent = -1
            continue
        }
        if ($indent -lt $kindIndent) { throw "Ontology '$Path': unexpected indentation at '$text'." }

        if ($actionsIndent -ge 0 -and $indent -le $actionsIndent) { $actionsIndent = -1 }
        if ($actionsIndent -lt 0) {
            if ($text -match '^actions:\s*(.*)$') {
                $rest = $Matches[1].Trim()
                if ($rest -eq '[]') { continue }
                if ($rest) { throw "Ontology '$Path': flow-style actions under $kind are not supported; use a block list." }
                $actionsIndent = $indent; $itemIndent = -1; $itemKeyIndent = -1
            }
            continue
        }

        # Inside actions: '- ' at the first item's column starts an item; its keys sit at the column after the dash.
        # A deeper '- ' belongs to a list inside an item (inputs: - { name: id, ... }) and is not an action.
        if ($text.StartsWith('- ') -and ($itemIndent -lt 0 -or $indent -eq $itemIndent)) {
            $itemIndent = $indent
            $itemKeyIndent = $indent + 2
            $text = $text.Substring(2).Trim()
            if ($text -match '^\{(.*)\}$') {
                if ($Matches[1] -match '(^|,)\s*name:\s*([^,}\s]+)') { $found.Add("$kind.$($Matches[2].Trim('''', '"'))") }
                continue
            }
        }
        elseif ($indent -ne $itemKeyIndent) { continue }
        if ($text -match '^name:\s*(\S+)\s*$') { $found.Add("$kind.$($Matches[1].Trim('''', '"'))") }
    }
    $found | Select-Object -Unique
}

# A path relative to the PowerShell location, made absolute for .NET (which resolves against the process cwd).
function Get-FullPath {
    param([Parameter(Mandatory)][string] $Path)
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

# The Kind.action pairs the given ontologies declare, plus this module's own tool ontology, sorted and unique.
function Get-DeclaredAction {
    param([string[]] $OntologyPath = @())

    $all = foreach ($p in @($script:ToolOntologyPath) + $OntologyPath) { Read-OntologyAction -Path $p }
    , [string[]]@($all | Sort-Object -Unique -CaseSensitive)
}

function Find-PolicySchema {
    foreach ($candidate in (Join-Path $script:ModuleRoot 'schemas/policy.schema.json'),
                           (Join-Path $script:ModuleRoot '../../schemas/policy.schema.json')) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [System.IO.Path]::GetFullPath($candidate) }
    }
    throw "policy.schema.json not found next to the module ('$script:ModuleRoot/schemas') or in the repo ('schemas/'). Pass -SchemaPath."
}

# Returns the policy as a hashtable and its JSON text, from a path or from an object New-Policy returned.
function Read-PolicyDocument {
    param([Parameter(Mandatory)][object] $Policy)

    if ($Policy -is [string]) {
        $Policy = Get-FullPath -Path $Policy
        if (-not (Test-Path -LiteralPath $Policy -PathType Leaf)) { throw "Policy not found at '$Policy'." }
        $json = [System.IO.File]::ReadAllText($Policy)
    }
    else {
        $json = $Policy | ConvertTo-Json -Depth 16
    }
    [pscustomobject]@{ Json = $json; Document = ($json | ConvertFrom-Json -AsHashtable) }
}

function ConvertTo-Hashtable {
    param([AllowNull()][object] $InputObject)

    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [string]) { return ($InputObject | ConvertFrom-Json -AsHashtable) }
    if ($InputObject -is [hashtable]) { return $InputObject }
    $InputObject | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
}

# Absolute POSIX path with . and .. folded, relative paths taken against $Cwd. On Linux, symlinks in the existing
# part of the path are resolved too (realpath -m), so /work/link-to-etc/x is judged as /etc/x.
function ConvertTo-PolicyPath {
    param(
        [AllowNull()][AllowEmptyString()][string] $Path,
        [Parameter(Mandatory)][string] $Cwd
    )

    if ([string]::IsNullOrEmpty($Path)) { return $null }
    if ($Path -eq '~' -or $Path.StartsWith('~/')) {
        if ($env:HOME -and $env:HOME.StartsWith('/')) { $Path = $env:HOME + $Path.Substring(1) }
    }
    if (-not $Path.StartsWith('/')) { $Path = $Cwd.TrimEnd('/') + '/' + $Path }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $Path.Split('/')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        if ($segment -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) }; continue }
        $parts.Add($segment)
    }
    $normal = '/' + ($parts -join '/')

    if ($IsLinux -and (Get-Command realpath -CommandType Application -ErrorAction Ignore)) {
        $real = & realpath -m -- $normal 2>$null
        if ($LASTEXITCODE -eq 0 -and $real) { $normal = "$real".Trim() }
    }
    $normal
}

# ** crosses directories, * and ? do not. 'dir/**' also matches 'dir' itself.
function Test-PolicyGlob {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Glob
    )

    $sb = [System.Text.StringBuilder]::new('^')
    $g = $Glob
    $tailAny = $g.EndsWith('/**')
    if ($tailAny) { $g = $g.Substring(0, $g.Length - 3) }
    for ($i = 0; $i -lt $g.Length; $i++) {
        $c = $g[$i]
        if ($c -eq '*' -and $i + 1 -lt $g.Length -and $g[$i + 1] -eq '*') { [void]$sb.Append('.*'); $i++ }
        elseif ($c -eq '*') { [void]$sb.Append('[^/]*') }
        elseif ($c -eq '?') { [void]$sb.Append('[^/]') }
        else { [void]$sb.Append([regex]::Escape([string]$c)) }
    }
    if ($tailAny) { [void]$sb.Append('(/.*)?') }
    [void]$sb.Append('$')
    [regex]::IsMatch($Path, $sb.ToString())
}

# Splits a shell command into simple commands (on ; & | && || newlines and parentheses), each a list of words
# with quotes removed. Lexical only: no expansion of variables, globs or command substitution.
function Split-ShellCommand {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Command)

    $commands = [System.Collections.Generic.List[object]]::new()
    $words = [System.Collections.Generic.List[string]]::new()
    $word = [System.Text.StringBuilder]::new()
    $inWord = $false
    $quote = [char]0

    for ($i = 0; $i -lt $Command.Length; $i++) {
        $c = $Command[$i]
        if ($quote -eq [char]"'") {
            if ($c -eq [char]"'") { $quote = [char]0 } else { [void]$word.Append($c) }
            continue
        }
        if ($quote -eq [char]'"') {
            if ($c -eq [char]'"') { $quote = [char]0 }
            elseif ($c -eq [char]'\' -and $i + 1 -lt $Command.Length -and '"\$`'.Contains($Command[$i + 1])) { $i++; [void]$word.Append($Command[$i]) }
            else { [void]$word.Append($c) }
            continue
        }
        if ($c -eq [char]"'" -or $c -eq [char]'"') { $quote = $c; $inWord = $true; continue }
        if ($c -eq [char]'\' -and $i + 1 -lt $Command.Length) {
            $i++
            if ($Command[$i] -ne "`n") { [void]$word.Append($Command[$i]); $inWord = $true }
            continue
        }
        if (";&|()`n".Contains($c)) {
            if ($inWord) { $words.Add($word.ToString()); [void]$word.Clear(); $inWord = $false }
            if ($words.Count) { $commands.Add([string[]]$words.ToArray()); $words.Clear() }
            continue
        }
        if ([char]::IsWhiteSpace($c)) {
            if ($inWord) { $words.Add($word.ToString()); [void]$word.Clear(); $inWord = $false }
            continue
        }
        [void]$word.Append($c); $inWord = $true
    }
    if ($inWord) { $words.Add($word.ToString()) }
    if ($words.Count) { $commands.Add([string[]]$words.ToArray()) }
    , $commands.ToArray()
}

# What a Bash command does, as targets {KindAction, Path}. Recognises rm, rmdir, unlink, shred and find -delete
# (behind env assignments and sudo/env/command/exec/nohup/nice/time/xargs/busybox); everything else is one
# Shell.exec target with no path. A best-effort lexical match, not a sandbox (design.md 2).
function Get-ShellTarget {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Command,
        [Parameter(Mandatory)][string] $Cwd
    )

    $wrappers = 'sudo', 'env', 'command', 'exec', 'nohup', 'nice', 'time', 'xargs', 'busybox', 'doas'
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($words in (Split-ShellCommand -Command $Command)) {
        $i = 0
        while ($i -lt $words.Count) {
            $w = $words[$i]
            $name = $w.Substring($w.LastIndexOf('/') + 1)
            if ($w -match '^[A-Za-z_][A-Za-z0-9_]*=' -or $w.StartsWith('-') -or $name -in $wrappers) { $i++; continue }
            break
        }
        if ($i -ge $words.Count) { continue }
        $name = $words[$i].Substring($words[$i].LastIndexOf('/') + 1)
        $argv = @(if ($i + 1 -lt $words.Count) { $words[($i + 1)..($words.Count - 1)] })

        $kindAction = $null
        $paths = @()
        switch -CaseSensitive ($name) {
            { $_ -in 'rm', 'unlink', 'shred', 'rmdir' } {
                $operands = [System.Collections.Generic.List[string]]::new()
                $recursive = $name -eq 'rmdir'
                $endOfOptions = $false
                foreach ($a in $argv) {
                    if (-not $endOfOptions -and $a -eq '--') { $endOfOptions = $true; continue }
                    if (-not $endOfOptions -and $a.StartsWith('-') -and $a.Length -gt 1) {
                        if ($name -eq 'rm' -and ($a -match '^-[A-Za-z]*[rR]' -or $a -eq '--recursive')) { $recursive = $true }
                        continue
                    }
                    if ($a -match '^\d*[<>]') { continue }
                    $operands.Add($a)
                }
                $kindAction = if ($recursive) { 'Directory.delete' } else { 'File.delete' }
                $paths = @(if ($operands.Count) { $operands } else { $null })
            }
            'find' {
                if ($argv -contains '-delete') {
                    $kindAction = 'File.delete'
                    # Start points are the operands before the first expression word.
                    $starts = @(foreach ($a in $argv) { if ($a.StartsWith('-') -or $a -in '(', '!') { break }; $a })
                    $paths = @(if ($starts.Count) { $starts } else { '.' })
                }
            }
        }
        if ($kindAction) {
            foreach ($p in $paths) { $targets.Add([pscustomobject]@{ KindAction = $kindAction; Path = (ConvertTo-PolicyPath -Path $p -Cwd $Cwd) }) }
        }
    }
    if ($targets.Count -eq 0) { $targets.Add([pscustomobject]@{ KindAction = 'Shell.exec'; Path = $null }) }
    , $targets.ToArray()
}

# The first rule for KindAction whose paths match decides; a rule without paths matches any target, including
# one whose path is unknown; nothing matching falls to the policy default.
function Resolve-PolicyTarget {
    param(
        [Parameter(Mandatory)][hashtable] $Document,
        [Parameter(Mandatory)][string] $KindAction,
        [AllowNull()][string] $Path
    )

    # [string] turns $null into ''; a target with no path records null.
    $target = if ($Path) { $Path } else { $null }
    $shown = if ($Path) { "$KindAction $Path" } else { $KindAction }
    $rules = @($Document.rules)
    for ($n = 0; $n -lt $rules.Count; $n++) {
        $r = $rules[$n]
        if ("$($r.kind).$($r.action)" -cne $KindAction) { continue }
        $globs = @(if ($r.ContainsKey('paths')) { $r.paths })
        $match = if ($globs.Count -eq 0) { $true }
                 elseif (-not $Path) { $false }
                 else { [bool]($globs | Where-Object { Test-PolicyGlob -Path $Path -Glob $_ } | Select-Object -First 1) }
        if (-not $match) { continue }
        $verb = @{ allow = 'allowed'; deny = 'denied'; witness = 'allowed and witnessed' }[$r.effect]
        $where = if ($globs.Count) { " (paths $($globs -join ', '))" } else { '' }
        return [pscustomobject]@{ effect = $r.effect; rule = "rules[$n]"; reason = "$shown $verb by policy rules[$n]$where"; kindAction = $KindAction; path = $target }
    }
    $why = if ($Path) { "matches no rule for $KindAction" } else { "has no path and no path-free rule for $KindAction applies" }
    [pscustomobject]@{ effect = $Document.default; rule = 'default'; reason = "$shown $why; policy default is $($Document.default)"; kindAction = $KindAction; path = $target }
}
