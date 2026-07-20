$errs = $null
$tok = $null
$path = (Resolve-Path publish/deploy-client-bundles.ps1).Path
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
  $errs | ForEach-Object { $_.ToString() }
  exit 1
}
Write-Output 'PARSE_OK'
