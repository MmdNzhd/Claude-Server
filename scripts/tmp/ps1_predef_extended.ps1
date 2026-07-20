Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Get-Location).Path
$files = Get-ChildItem -Path (Join-Path $ProjectRoot 'scripts/client') -Recurse -Filter '*.ps1' | Sort-Object FullName

function Analyze-File {
    param([string]$Path)
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if (-not $ast) { return @() }

    $timeline = [System.Collections.Generic.List[object]]::new()
    foreach ($stmt in $ast.EndBlock.Statements) {
        if ($stmt -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            [void]$timeline.Add([pscustomobject]@{ Kind='def'; Name=$stmt.Name; Line=$stmt.Extent.StartLineNumber; Stmt=$stmt })
        } elseif ($stmt -is [System.Management.Automation.Language.TrapStatementAst]) {
            continue
        } else {
            [void]$timeline.Add([pscustomobject]@{ Kind='exec'; Name=$null; Line=$stmt.Extent.StartLineNumber; Stmt=$stmt })
        }
    }

    $defs = @{}
    $fails = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $timeline) {
        if ($item.Kind -eq 'def') {
            if (-not $defs.ContainsKey($item.Name)) { $defs[$item.Name] = $item.Line }
            continue
        }
        $item.Stmt.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object {
                $cmd = $_
                if ($cmd.CommandElements.Count -eq 0) { return }
                $first = $cmd.CommandElements[0]
                if ($first -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return }
                $name = $first.Value
                if ($name -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') { return }
                if ($defs.ContainsKey($name) -and $item.Line -lt $defs[$name]) {
                    [void]$fails.Add([pscustomobject]@{ Function=$name; DefLine=$defs[$name]; CallLine=$item.Line })
                } elseif (-not $defs.ContainsKey($name)) {
                    $later = $timeline | Where-Object { $_.Kind -eq 'def' -and $_.Name -eq $name -and $_.Line -gt $item.Line } | Select-Object -First 1
                    if ($later) {
                        [void]$fails.Add([pscustomobject]@{ Function=$name; DefLine=$later.Line; CallLine=$item.Line })
                    }
                }
            }
    }
    return ,@($fails)
}

$allFails = @(); $passed = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($ProjectRoot.Length).TrimStart('\','/').Replace('\','/')
    $fails = @(Analyze-File -Path $f.FullName)
    if ($fails.Count -gt 0) {
        $seen = @{}
        foreach ($ff in ($fails | Sort-Object CallLine)) {
            $k = $ff.Function.ToLower()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $allFails += [pscustomobject]@{ File=$rel; Function=$ff.Function; DefLine=$ff.DefLine; CallLine=$ff.CallLine }
        }
    } else { $passed += $rel }
}

Write-Output 'FAILS_START'
foreach ($x in $allFails) { Write-Output ("{0}|{1}|{2}|{3}" -f $x.File, $x.Function, $x.DefLine, $x.CallLine) }
Write-Output 'FAILS_END'
Write-Output ("PASS_COUNT={0}" -f $passed.Count)
Write-Output ("FAIL_COUNT={0}" -f $allFails.Count)
Write-Output ("OVERALL={0}" -f ($(if ($allFails.Count -gt 0) { 'FAIL' } else { 'PASS' })))
