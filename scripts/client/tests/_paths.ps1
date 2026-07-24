# Shared paths for client test scripts (dot-source from tests/*.ps1)
$script:TestsDir    = $PSScriptRoot
$script:ClientRoot   = Split-Path -Parent $TestsDir
$script:ScriptsRoot  = Split-Path -Parent $script:ClientRoot
$script:RepoRoot     = Split-Path -Parent $script:ScriptsRoot

function Get-ClientFile([string]$Rel) {
    Join-Path $script:ClientRoot ($Rel -replace '/', '\\')
}

function Get-ServerFile([string]$Rel) {
    Join-Path $script:ScriptsRoot ($Rel -replace '/', '\\')
}

function Get-ConnectVersion {
    $f = Get-ClientFile 'windows\\connect.ps1'
    $raw = Get-Content $f -Raw
    if ($raw -match "ConnectVersion = '([^']+)'") { return $Matches[1] }
    throw 'ConnectVersion not found in windows/connect.ps1'
}

# Brace-matching extractor used by "LIVE" tests to pull one real function body verbatim out
# of a production client script and dot-source it in isolation, so those tests exercise the
# exact shipped code path (not a re-implementation) without inheriting that file's full
# module-load-time side effects (UI init, mutexes, global state, etc). Safe through embedded
# here-strings (e.g. Add-Type C# blocks): as long as the embedded content itself has balanced
# braces - true for any syntactically valid C#/JSON/etc - the running depth count can only
# return to 0 at the real end of the outer PowerShell function.
function Get-FunctionSource {
    param([string]$Content, [string]$Name)
    $m = [regex]::Match($Content, "function\s+$Name\b")
    if (-not $m.Success) { return $null }
    $start = $m.Index
    $i = $Content.IndexOf('{', $start)
    $depth = 0
    for ($j = $i; $j -lt $Content.Length; $j++) {
        if ($Content[$j] -eq '{') { $depth++ }
        elseif ($Content[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $Content.Substring($start, $j - $start + 1) } }
    }
    return $null
}
