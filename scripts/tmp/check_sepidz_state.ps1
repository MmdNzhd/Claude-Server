$ErrorActionPreference = 'Continue'
Write-Host '=== LIVE SEPIDZ ==='
ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "ls /usr/local/share/claude-client/; echo ---; cat /usr/local/share/claude-client/connect-version.txt; echo; grep -E 'ServerIP|192.168' /usr/local/share/claude-client/connect.ps1 | head -3; ls -la /usr/local/share/claude-client/connect-update.ps1"
Write-Host '=== LIVE SMART ==='
ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt"
Write-Host '=== DESKTOP FOLDERS ==='
$dirs = @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
)
foreach ($d in $dirs) {
  if (Test-Path $d) {
    $v = (Get-Content (Join-Path $d 'connect-version.txt') -Raw).Trim()
    $ip = [regex]::Match((Get-Content (Join-Path $d 'connect.ps1') -Raw), '192\.168\.\d+\.\d+').Value
    Write-Host "$d => ver=$v ip=$ip"
  } else {
    Write-Host "MISSING $d"
  }
}
