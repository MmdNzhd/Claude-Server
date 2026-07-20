$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

Write-Host '======== REPO GIT POLICY ========'
$mount = Get-Content "$root\scripts\server\claude-mount.sh" -Raw
@(
  @{N='SCM policy fn'; Ok=($mount -match '_apply_git_scm_policy')},
  @{N='User-only settings'; Ok=($mount -match 'Only remote User settings')},
  @{N='git.enabled False'; Ok=($mount -match '"git.enabled": False')},
  @{N='no shim in repo'; Ok=(-not (Test-Path "$root\scripts\server\git-via-laptop-exec.sh"))}
) | ForEach-Object {
  if ($_.Ok) { Write-Host "OK  $($_.N)" } else { Write-Host "FAIL $($_.N)" }
}

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -o ConnectTimeout=8 -q "$root\scripts\tmp\git_deep_audit.py" 'sepidz@192.168.250.70:/tmp/git_deep_audit.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/git_deep_audit.py' + $nl +
  'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\gda.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\gda.sh" 'sepidz@192.168.250.70:/tmp/gda.sh'

$outFile = "$env:TEMP\gda_out.txt"
$errFile = "$env:TEMP\gda_err.txt"
Remove-Item $outFile,$errFile -ErrorAction SilentlyContinue
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/gda.sh') -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
if (-not $p.WaitForExit(300000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT'; exit 1 }
$liveOut = if (Test-Path $outFile) { Get-Content $outFile -Raw } else { '' }
Write-Host $liveOut
if (Test-Path $errFile) { $e = Get-Content $errFile -Raw; if ($e) { Write-Host $e } }

if ($liveOut -match 'GIT_DEEP_GREEN' -and $liveOut -match 'fail=0') {
  Write-Host 'ALL_GIT_DEEP_GREEN'
  exit 0
}
Write-Host 'ALL_GIT_DEEP_RED'
exit 1
