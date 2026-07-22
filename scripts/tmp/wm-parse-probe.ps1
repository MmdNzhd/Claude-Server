$ErrorActionPreference = 'Continue'
Write-Host '=== AST parse of buggy Read line ==='
$code = @'
$raw = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
'@
$tok=$null; $err=$null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tok, [ref]$err)
$ast.EndBlock.Statements[0] | Format-List * | Out-String | Write-Host
# Dump nested structure
function Dump-Ast($node, $indent=0) {
  if ($null -eq $node) { return }
  $pad = ' ' * $indent
  $t = $node.GetType().Name
  $ext = ''
  if ($node -is [System.Management.Automation.Language.CommandAst]) {
    $ext = ' CMD=' + (($node.CommandElements | ForEach-Object { $_.Extent.Text }) -join ' || ')
  } elseif ($node -is [System.Management.Automation.Language.CommandParameterAst]) {
    $ext = ' PARAM=' + $node.ParameterName + ' ARG=' + $(if($node.Argument){$node.Argument.Extent.Text}else{'<none>'})
  } elseif ($node -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
    $ext = ' STR=' + $node.Value
  } elseif ($node -is [System.Management.Automation.Language.BinaryExpressionAst]) {
    $ext = ' BIN=' + $node.Operator + ' L=' + $node.Left.Extent.Text + ' R=' + $node.Right.Extent.Text
  }
  Write-Host ($pad + $t + ' [' + $node.Extent.Text.Substring(0, [Math]::Min(80,$node.Extent.Text.Length)) + ']' + $ext)
  foreach ($p in $node.PSObject.Properties) {
    $v = $p.Value
    if ($v -is [System.Management.Automation.Language.Ast]) { Dump-Ast $v ($indent+2) }
    elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
      foreach ($i in $v) { if ($i -is [System.Management.Automation.Language.Ast]) { Dump-Ast $i ($indent+2) } }
    }
  }
}
Dump-Ast $ast.EndBlock.Statements[0]

Write-Host ''
Write-Host '=== Runtime: buggy vs fixed ==='
$wp = Join-Path $env:TEMP 'wm-parse-test.txt'
Set-Content -LiteralPath $wp -Value '524288' -Encoding ASCII -NoNewline

# Buggy form (as in connect-ui.ps1)
$rawBuggy = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
Write-Host ("BUGGY raw=[{0}] len={1}" -f $rawBuggy, $rawBuggy.Length)

# Fixed form (as in connect-update.ps1)
$rawFixed = ((Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue) + '').Trim()
Write-Host ("FIXED raw=[{0}] len={1}" -f $rawFixed, $rawFixed.Length)

# What is -ErrorAction actually receiving?
Write-Host ''
Write-Host '=== Trace ErrorAction binding ==='
# Use a command that shows bound params
function Show-EA {
  param([Parameter(ValueFromRemainingArguments=$true)]$Rest)
  $PSBoundParameters | Format-List | Out-String | Write-Host
}
# Simulate via Get-Content with -Verbose and missing file
$missing = Join-Path $env:TEMP 'wm-missing-xyz.txt'
Remove-Item $missing -Force -ErrorAction SilentlyContinue
try {
  $x = (Get-Content -LiteralPath $missing -Raw -ErrorAction SilentlyContinue + '').Trim()
  Write-Host ("missing+buggy => [{0}] (no throw)" -f $x)
} catch {
  Write-Host ("missing+buggy THREW: " + $_.Exception.Message)
}
try {
  $x = ((Get-Content -LiteralPath $missing -Raw -ErrorAction SilentlyContinue) + '').Trim()
  Write-Host ("missing+fixed => [{0}] (no throw)" -f $x)
} catch {
  Write-Host ("missing+fixed THREW: " + $_.Exception.Message)
}

# Critical: does buggy form pass '' as a second path?
Write-Host ''
Write-Host '=== Does + empty become second path? ==='
$out = Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '' 2>&1
Write-Host ("Get-Content result type: " + $out.GetType().FullName)
if ($out -is [System.Array]) {
  Write-Host ("Array length: " + $out.Length)
  $out | ForEach-Object { Write-Host ("  elem: [{0}] type={1}" -f $_, $_.GetType().FullName) }
} else {
  Write-Host ("Single: [{0}]" -f $out)
}

Remove-Item $wp -Force
