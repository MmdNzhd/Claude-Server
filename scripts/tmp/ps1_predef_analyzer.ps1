Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Get-Location).Path
$files = Get-ChildItem -Path (Join-Path $ProjectRoot 'scripts/client') -Recurse -Filter '*.ps1' |
    Sort-Object FullName

function Get-FunctionDefLines {
    param([string]$Path)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if (-not $ast) { return @{}, @() }

    $defs = @{}
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object {
            $name = $_.Name
            $line = $_.Extent.StartLineNumber
            if (-not $defs.ContainsKey($name)) {
                $defs[$name] = $line
            }
        }
    return $defs, $ast
}

function Get-ImmediateScriptBodyStatements {
    param($Ast)
    $stmts = [System.Collections.Generic.List[object]]::new()
    if ($Ast -is [System.Management.Automation.Language.ScriptBlockAst]) {
        foreach ($s in $Ast.EndBlock.Statements) { [void]$stmts.Add($s) }
        return $stmts
    }
    return @()
}

function Test-StatementIsFunctionDef {
    param($Statement)
    return ($Statement -is [System.Management.Automation.Language.FunctionDefinitionAst])
}

function Get-CalledNamesFromStatement {
    param($Statement)
    $names = [System.Collections.Generic.List[string]]::new()
    $Statement.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object {
            $cmd = $_
            if ($cmd.CommandElements.Count -eq 0) { return }
            $first = $cmd.CommandElements[0]
            $name = $null
            if ($first -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $name = $first.Value
            } elseif ($first -is [System.Management.Automation.Language.VariableExpressionAst]) {
                return
            } else {
                return
            }
            if ($name -match '^[A-Za-z][A-Za-z0-9_-]*$') {
                [void]$names.Add($name)
            }
        }
    return ,$names.ToArray()
}

function Get-TopLevelExecutableStatements {
    param($Ast)
    # Walk script-level statements until first function def; also collect
    # statements between function defs that execute immediately (not inside func/trap)
    $result = [System.Collections.Generic.List[object]]::new()
    $endBlock = $Ast.EndBlock
    if (-not $endBlock) { return @() }

    foreach ($stmt in $endBlock.Statements) {
        if ($stmt -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            continue
        }
        if ($stmt -is [System.Management.Automation.Language.TrapStatementAst]) {
            continue
        }
        if ($stmt -is [System.Management.Automation.Language.TypeDefinitionAst]) {
            continue
        }
        if ($stmt -is [System.Management.Automation.Language.UsingStatementAst]) {
            continue
        }
        [void]$result.Add($stmt)
    }
    return ,$result.ToArray()
}

$allFails = @()
$passed = @()

foreach ($f in $files) {
    $rel = $f.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
    $defs, $ast = Get-FunctionDefLines -Path $f.FullName
    if ($defs.Count -eq 0) {
        $passed += $rel
        continue
    }

    $topStmts = Get-TopLevelExecutableStatements -Ast $ast
    $fileFails = @()
    foreach ($stmt in $topStmts) {
        $line = $stmt.Extent.StartLineNumber
        foreach ($name in (Get-CalledNamesFromStatement -Statement $stmt)) {
            if ($defs.ContainsKey($name)) {
                $defLine = $defs[$name]
                if ($line -lt $defLine) {
                    $fileFails += [pscustomobject]@{
                        Function = $name
                        DefLine  = $defLine
                        CallLine = $line
                    }
                }
            }
        }
    }

    if ($fileFails.Count -gt 0) {
        $seen = @{}
        foreach ($ff in ($fileFails | Sort-Object CallLine)) {
            $k = $ff.Function.ToLower()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $allFails += [pscustomobject]@{
                File     = $rel
                Function = $ff.Function
                DefLine  = $ff.DefLine
                CallLine = $ff.CallLine
            }
        }
    } else {
        $passed += $rel
    }
}

Write-Output 'FAILS_START'
foreach ($x in $allFails) {
    Write-Output ("{0}|{1}|{2}|{3}" -f $x.File, $x.Function, $x.DefLine, $x.CallLine)
}
Write-Output 'FAILS_END'
Write-Output ("PASS_COUNT={0}" -f $passed.Count)
Write-Output ("FAIL_COUNT={0}" -f $allFails.Count)
Write-Output ("TOTAL={0}" -f $files.Count)
Write-Output ("OVERALL={0}" -f ($(if ($allFails.Count -gt 0) { 'FAIL' } else { 'PASS' })))
foreach ($p in $passed) { Write-Output "PASS:$p" }
