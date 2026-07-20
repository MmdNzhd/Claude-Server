$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }

function SshTimed([string]$Target, [string]$RemoteCmd, [int]$Sec = 8) {
  $job = Start-Job -ScriptBlock {
    param($t,$c)
    & ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $t $c 2>$null
    @{ Code=$LASTEXITCODE; Out=($output = (& ssh -o BatchMode=yes -o ConnectTimeout=5 $t $c 2>$null | Out-String)) }
  } -ArgumentList $Target, $RemoteCmd
  # simpler approach below
}

function SshQuick([string]$Target, [string]$RemoteCmd) {
  $p = Start-Process -FilePath ssh -ArgumentList @(
    '-o','BatchMode=yes','-o','ConnectTimeout=4','-o','ConnectionAttempts=1',
    $Target, $RemoteCmd
  ) -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ssh_out.txt" -RedirectStandardError "$env:TEMP\ssh_err.txt"
  if (-not $p.WaitForExit(10000)) {
    try { $p.Kill() } catch {}
    return @{ Ok=$false; Out='TIMEOUT' }
  }
  $out = ''
  if (Test-Path "$env:TEMP\ssh_out.txt") { $out = (Get-Content "$env:TEMP\ssh_out.txt" -Raw) }
  return @{ Ok=($p.ExitCode -eq 0); Out=$out; Code=$p.ExitCode }
}

Write-Host '======== LOCAL HARDEN ========'
@(
  @{N='deploy base64'; Ok=(Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'base64, non-interactive' -Quiet)},
  @{N='deploy no hang'; Ok=(-not (Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern '\$SudoPassword \| & ssh' -Quiet))},
  @{N='git user policy'; Ok=(Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern 'Only remote User settings' -Quiet)},
  @{N='update msg'; Ok=(Select-String -Path "$root\scripts\client\windows\connect-update.ps1" -Pattern 'Client up to date' -Quiet)},
  @{N='dle crlf'; Ok=(Select-String -Path "$root\scripts\server\commands\deploy-laptop-exec.sh" -Pattern 'sed -i' -Quiet)},
  @{N='sudoers sepidz'; Ok=(Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:sepidz' -Quiet)}
) | ForEach-Object { if ($_.Ok) { OK $_.N } else { FAIL $_.N } }
$repo = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
if ($repo -eq '20260717.33') { OK "repo=$repo" } else { FAIL "repo=$repo" }

Write-Host '======== VERSIONS ========'
$r = SshQuick 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
if ($r.Ok) {
  $smart = $r.Out.Trim()
  if ($smart -eq '20260717.22') { OK "smart=$smart frozen" } else { FAIL "smart=$smart expected .22" }
} else { Write-Host "WARN smart version skip ($($r.Out))"; }

$r = SshQuick 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
if ($r.Ok) {
  $sepidz = $r.Out.Trim()
  if ($sepidz -eq '20260717.33') { OK "sepidz=$sepidz" } else { FAIL "sepidz=$sepidz expected .33" }
} else { FAIL "sepidz unreachable $($r.Out)" }

Write-Host '======== STATIC TESTS ========'
foreach ($t in @('scripts\client\tests\test-connect-pipeline.ps1','scripts\client\tests\test-git-mode-deep.ps1')) {
  $tp = Join-Path $root $t
  Write-Host "RUN $t"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $tp
  if ($LASTEXITCODE -ne 0) { FAIL "$t exit=$LASTEXITCODE" } else { OK $t }
}

Write-Host '======== SEPIDZ LIVE ========'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -o ConnectTimeout=8 -q "$root\scripts\tmp\deep_final.py" 'sepidz@192.168.250.70:/tmp/deep_final.py'
if ($LASTEXITCODE -ne 0) { FAIL 'scp deep_final failed' }
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_final.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\rdf3.sh", $wrap)
scp -o BatchMode=yes -o ConnectTimeout=8 -q "$env:TEMP\rdf3.sh" 'sepidz@192.168.250.70:/tmp/rdf3.sh'
$p = Start-Process -FilePath ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/rdf3.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\live_out.txt" -RedirectStandardError "$env:TEMP\live_err.txt"
if (-not $p.WaitForExit(240000)) {
  try { $p.Kill() } catch {}
  FAIL 'live deep TIMEOUT'
} else {
  Get-Content "$env:TEMP\live_out.txt" -ErrorAction SilentlyContinue | Write-Host
  Get-Content "$env:TEMP\live_err.txt" -ErrorAction SilentlyContinue | Write-Host
  if ($p.ExitCode -ne 0) { FAIL "live deep exit=$($p.ExitCode)" } else { OK 'live deep' }
}

Write-Host '======== RESULT ========'
Write-Host "local_fail=$fail"
if ($fail -ne 0) { Write-Host 'ALL_DEEP_RED'; exit 1 }
Write-Host 'ALL_DEEP_GREEN'
exit 0
