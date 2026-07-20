$ErrorActionPreference = 'Continue'
function SshQuick($Target, $Cmd) {
  $out = Join-Path $env:TEMP ("v_" + [guid]::NewGuid().ToString('N') + ".txt")
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=6','-o','ConnectionAttempts=1',$Target,$Cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  if (-not $p.WaitForExit(12000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  if (Test-Path $out) { return (Get-Content $out -Raw).Trim() }
  return 'EMPTY'
}
$smart = SshQuick 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt; echo ---; ls /usr/local/share/claude-client/ 2>/dev/null | head -20'
$sepidz = SshQuick 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
$repo = (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
Write-Host "SMART_BUNDLE:"
Write-Host $smart
Write-Host "SEPIDZ=$sepidz"
Write-Host "REPO=$repo"
if (($smart -split "`n")[0].Trim() -ne '20260717.22') { Write-Host 'FAIL smart not 22'; exit 1 }
Write-Host 'SMART_LOCKED_22_OK'
