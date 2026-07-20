$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }
function WARN($m){ Write-Host "WARN $m" }

function SshQuick([string]$Target, [string]$RemoteCmd) {
  $out = Join-Path $env:TEMP ("sshq_" + [guid]::NewGuid().ToString('N') + ".txt")
  $err = "$out.err"
  $p = Start-Process -FilePath ssh -ArgumentList @(
    '-o','BatchMode=yes','-o','ConnectTimeout=4','-o','ConnectionAttempts=1', $Target, $RemoteCmd
  ) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(10000)) { try { $p.Kill() } catch {}; return @{ Ok=$false; Out='TIMEOUT' } }
  $txt = if (Test-Path $out) { (Get-Content $out -Raw).Trim() } else { '' }
  return @{ Ok=($p.ExitCode -eq 0 -and $txt.Length -gt 0); Out=$txt; Code=$p.ExitCode }
}

Write-Host '======== 1) LOCAL HARDEN ========'
@(
  @{ N='deploy base64'; Ok=(Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'base64, non-interactive' -Quiet) },
  @{ N='deploy no hang'; Ok=(-not (Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern '\$SudoPassword \| & ssh' -Quiet)) },
  @{ N='git Cursor OFF policy'; Ok=(Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern 'Only remote User settings' -Quiet) },
  @{ N='git.enabled False'; Ok=(Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern '"git.enabled": False' -Quiet) },
  @{ N='no git shim file'; Ok=(-not (Test-Path "$root\scripts\server\git-via-laptop-exec.sh")) },
  @{ N='update msg'; Ok=(Select-String -Path "$root\scripts\client\windows\connect-update.ps1" -Pattern 'Client up to date' -Quiet) },
  @{ N='dle crlf'; Ok=(Select-String -Path "$root\scripts\server\commands\deploy-laptop-exec.sh" -Pattern 'sed -i' -Quiet) },
  @{ N='sudoers sepidz'; Ok=(Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:sepidz' -Quiet) },
  @{ N='sudoers smart'; Ok=(Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:smart' -Quiet) }
) | ForEach-Object { if ($_.Ok) { OK $_.N } else { FAIL $_.N } }

$repo = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
if ($repo -eq '20260717.33') { OK "repo=$repo" } else { FAIL "repo=$repo" }

Write-Host '======== 2) VERSIONS ========'
$r = SshQuick 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
if ($r.Out -eq '20260717.22') { OK "smart=$($r.Out) frozen" }
elseif ($r.Out -match '20260717') { FAIL "smart=$($r.Out) expected .22" }
else { WARN "smart version skip ($($r.Out))" }

$r = SshQuick 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
if ($r.Out -eq '20260717.33') { OK "sepidz=$($r.Out)" }
elseif ($r.Out -match '20260717') { FAIL "sepidz=$($r.Out) expected .33" }
else { FAIL "sepidz unreachable ($($r.Out))" }

Write-Host '======== 3) STATIC TESTS ========'
foreach ($t in @('scripts\client\tests\test-connect-pipeline.ps1','scripts\client\tests\test-git-mode-deep.ps1')) {
  Write-Host "RUN $t"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $t) | Out-Null
  if ($LASTEXITCODE -ne 0) { FAIL "$t exit=$LASTEXITCODE" } else { OK $t }
}

Write-Host '======== 4) SEPIDZ LIVE MATRIX ========'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -o ConnectTimeout=8 -q "$root\scripts\tmp\sys_check_all.py" 'sepidz@192.168.250.70:/tmp/sys_check_all.py'
if ($LASTEXITCODE -ne 0) { FAIL 'scp sys_check_all failed' }

$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/sys_check_all.py' + $nl +
  'ec=$?' + $nl + 'echo WRAPPER_EC=$ec' + $nl + 'exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\sysc.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\sysc.sh" 'sepidz@192.168.250.70:/tmp/sysc.sh'

$outFile = "$env:TEMP\sysc_out.txt"
$errFile = "$env:TEMP\sysc_err.txt"
Remove-Item $outFile,$errFile -ErrorAction SilentlyContinue
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/sysc.sh') -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
if (-not $p.WaitForExit(240000)) {
  try { $p.Kill() } catch {}
  FAIL 'live TIMEOUT'
} else {
  $liveOut = if (Test-Path $outFile) { Get-Content $outFile -Raw } else { '' }
  $liveErr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }
  Write-Host $liveOut
  if ($liveErr) { Write-Host $liveErr }
  $ec = $p.ExitCode
  if ($null -eq $ec) { $ec = -1 }
  # Prefer explicit markers from remote script (Start-Process ExitCode can be flaky)
  if ($liveOut -match 'SYS_GREEN' -and $liveOut -match 'fail=0') {
    OK 'live matrix SYS_GREEN'
  } elseif ($liveOut -match 'SYS_RED' -or $liveOut -match 'fail=[1-9]') {
    FAIL 'live matrix SYS_RED'
  } elseif ($ec -eq 0) {
    OK 'live matrix exit=0'
  } else {
    FAIL "live exit=$ec"
  }
}

Write-Host '======== RESULT ========'
Write-Host "local_fail=$fail"
if ($fail -ne 0) { Write-Host 'ALL_SYS_RED'; exit 1 }
Write-Host 'ALL_SYS_GREEN'
exit 0
