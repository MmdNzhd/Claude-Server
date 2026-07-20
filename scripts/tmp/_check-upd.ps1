$p = 'scripts\client\windows\connect-update.ps1'
$c = Get-Content -LiteralPath $p -Raw
'lines=' + @($c -split "`n").Count
'hasChecksum=' + $c.Contains('Test-BundleChecksums')
'hasSwap=' + $c.Contains('Swap-LiveDir')
'hasIA=' + $c.Contains('IdentityAgent')
'hasNewRoot=' + $c.Contains('.client-update-new')
$e=$null;$t=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $p), [ref]$t, [ref]$e)
if ($e -and $e.Count -gt 0) { 'PARSE_FAIL'; $e | ForEach-Object { $_.ToString() }; exit 1 }
'PARSE_OK'
