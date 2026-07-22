$ErrorActionPreference='Stop'
function Test-Parse([string]$Path) {
  $e=$null; $t=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Path), [ref]$t, [ref]$e)
  if ($e -and $e.Count -gt 0) {
    Write-Host ("PARSE FAIL {0}" -f $Path)
    $e | ForEach-Object { Write-Host $_.ToString() }
    return $false
  }
  Write-Host ("PARSE OK {0}" -f $Path)
  return $true
}
$ok = $true
if (-not (Test-Parse 'publish\publish.ps1')) { $ok = $false }
if (-not (Test-Parse 'scripts\client\windows\connect-bootstrap.ps1')) { $ok = $false }
if (-not $ok) { exit 1 }
