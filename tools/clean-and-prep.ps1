$ErrorActionPreference = 'Continue'
Write-Host '=== kill connect sessions ==='
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  $cl = [string]$_.CommandLine
  $cl -match 'connect-boot\.ps1' -or $cl -match 'Claude-Connect\\connect\.ps1' -or $cl -match 'connect-update\.ps1'
} | ForEach-Object {
  Write-Host (" kill pid={0}" -f $_.ProcessId)
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

$desk = Join-Path $env:USERPROFILE 'Desktop'
$junk = @(
  (Join-Path $desk 'Claude-Connect-ExternalUser'),
  (Join-Path $env:TEMP 'claude-connect-setup.log')
)
foreach ($j in $junk) {
  if (Test-Path -LiteralPath $j) {
    Write-Host (" remove {0}" -f $j)
    Remove-Item -LiteralPath $j -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# Keep one Desktop EXE name: Claude-Connect.exe (remove Setup duplicate if identical)
$exe = Join-Path $desk 'Claude-Connect.exe'
$setup = Join-Path $desk 'Claude-Connect-Setup.exe'
if ((Test-Path $exe) -and (Test-Path $setup)) {
  $h1 = (Get-FileHash $exe -Algorithm SHA256).Hash
  $h2 = (Get-FileHash $setup -Algorithm SHA256).Hash
  if ($h1 -eq $h2) {
    Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue
    Write-Host ' removed duplicate Claude-Connect-Setup.exe'
  }
}

Write-Host '=== desktop left ==='
Get-ChildItem $desk -Filter '*Claude*' | ForEach-Object { Write-Host (" {0}" -f $_.Name) }

# Parse check connect-update
$upd = Join-Path (Get-Location) 'scripts\client\windows\connect-update.ps1'
$errs = $null
$tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($upd, [ref]$tok, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
  Write-Host 'PARSE FAIL connect-update.ps1'
  $errs | ForEach-Object { Write-Host $_.ToString() }
  exit 1
}
Write-Host 'PARSE OK connect-update.ps1'
exit 0
