$ErrorActionPreference = 'Continue'

# 1) AST of the exact buggy expression
$code = '$raw = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '''').Trim()'
$tok=$null; $err=$null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tok, [ref]$err)
Write-Host 'ERRORS:' 
$err | ForEach-Object { Write-Host $_.ToString() }

# Find CommandAst / BinaryExpressionAst in tree
$cmds = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true)
foreach ($c in $cmds) {
  Write-Host ('CMD: ' + $c.Extent.Text)
  foreach ($el in $c.CommandElements) {
    Write-Host ('  EL type=' + $el.GetType().Name + ' text=[' + $el.Extent.Text + ']')
    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
      $arg = $el.Argument
      Write-Host ('    PARAM -' + $el.ParameterName + ' argType=' + $(if($arg){$arg.GetType().Name}else{'null'}) + ' argText=[' + $(if($arg){$arg.Extent.Text}else{'null'}) + ']')
    }
  }
}
$bins = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)
foreach ($b in $bins) {
  Write-Host ('BIN op=' + $b.Operator + ' left=[' + $b.Left.Extent.Text + '] right=[' + $b.Right.Extent.Text + ']')
}

Write-Host '--- runtime ---'
$wp = Join-Path $env:TEMP 'wm-parse-test.txt'
[IO.File]::WriteAllText($wp, '524288')

# Exact buggy line from connect-ui
$raw = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
Write-Host ('buggy raw=[' + $raw + '] TryParse=' + [int]::TryParse($raw, [ref]([int]$n=0)))
$n=0
$ok=[int]::TryParse($raw, [ref]$n)
Write-Host ('buggy parse ok=' + $ok + ' n=' + $n)

$raw2 = ((Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue) + '').Trim()
$n2=0
$ok2=[int]::TryParse($raw2, [ref]$n2)
Write-Host ('fixed parse ok=' + $ok2 + ' n=' + $n2)

# Read real watermark with BOTH methods
$realWm = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log.sync-offset'
Write-Host ('real wm path=' + $realWm + ' exists=' + (Test-Path $realWm))
if (Test-Path $realWm) {
  $rawB = (Get-Content -LiteralPath $realWm -Raw -ErrorAction SilentlyContinue + '').Trim()
  $rawF = ((Get-Content -LiteralPath $realWm -Raw -ErrorAction SilentlyContinue) + '').Trim()
  $nb=0; $nf=0
  [void][int]::TryParse($rawB, [ref]$nb)
  [void][int]::TryParse($rawF, [ref]$nf)
  Write-Host ('real buggy=[' + $rawB + '] n=' + $nb)
  Write-Host ('real fixed=[' + $rawF + '] n=' + $nf)
  Write-Host ('file bytes hex=' + ([BitConverter]::ToString([IO.File]::ReadAllBytes($realWm))))
}

Remove-Item $wp -Force
