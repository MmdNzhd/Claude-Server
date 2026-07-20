$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$fail = 0
function OK([string]$m) { Write-Host "OK  $m" }
function FAIL([string]$m) { Write-Host "FAIL $m"; $script:fail++ }
function WARN([string]$m) { Write-Host "WARN $m" }

Write-Host '======== 1) LOCAL HARDEN ========'
$checks = @(
  @{ N='deploy base64 path'; P={ Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'base64, non-interactive' -Quiet } },
  @{ N='deploy no hang pipe'; P={ -not (Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern '\$SudoPassword \| & ssh' -Quiet) } },
  @{ N='git SCM user policy'; P={ Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern 'Only remote User settings' -Quiet } },
  @{ N='git SCM called'; P={ Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern '_apply_git_scm_policy' -Quiet } },
  @{ N='update up-to-date msg'; P={ Select-String -Path "$root\scripts\client\windows\connect-update.ps1" -Pattern 'Client up to date' -Quiet } },
  @{ N='dle CRLF sed'; P={ Select-String -Path "$root\scripts\server\commands\deploy-laptop-exec.sh" -Pattern "sed -i" -Quiet } },
  @{ N='sudoers sepidz'; P={ Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:sepidz' -Quiet } },
  @{ N='sudoers smart'; P={ Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:smart' -Quiet } }
)
foreach ($c in $checks) {
  $ok = & $c.P
  if ($ok) { OK $c.N } else { FAIL $c.N }
}

Write-Host '======== 2) VERSIONS ========'
$repo = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
Write-Host "REPO=$repo"
if ($repo -ne '20260717.33') { FAIL "repo version=$repo" } else { OK "repo=20260717.33" }

$smart = (ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt' 2>$null)
if (-not $smart) { FAIL 'smart version unreachable' }
else {
  $smart = $smart.Trim()
  Write-Host "SMART=$smart"
  if ($smart -ne '20260717.22') { FAIL "smart expected 20260717.22 got $smart" } else { OK 'smart frozen .22' }
}

$sepidz = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt' 2>$null)
if (-not $sepidz) { FAIL 'sepidz version unreachable' }
else {
  $sepidz = $sepidz.Trim()
  Write-Host "SEPIDZ=$sepidz"
  if ($sepidz -ne '20260717.33') { FAIL "sepidz expected .33 got $sepidz" } else { OK 'sepidz .33' }
}

Write-Host '======== 3) STATIC CLIENT TESTS ========'
$tests = @(
  'scripts\client\tests\test-connect-pipeline.ps1',
  'scripts\client\tests\test-git-mode-deep.ps1'
)
foreach ($t in $tests) {
  $tp = Join-Path $root $t
  if (-not (Test-Path $tp)) { WARN "missing $t"; continue }
  Write-Host "RUN $t"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $tp
  if ($LASTEXITCODE -ne 0) { FAIL "$t exit=$LASTEXITCODE" } else { OK "$t passed" }
}

Write-Host '======== 4) SEPIDZ LIVE DEEP ========'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q "$root\scripts\tmp\deep_all_check.py" 'sepidz@192.168.250.70:/tmp/deep_all_check.py'
scp -o BatchMode=yes -q "$root\scripts\tmp\sepidz_io_retest.py" 'sepidz@192.168.250.70:/tmp/sepidz_io_retest.py'

$syspy = @'
import os
cm=open("/usr/local/lib/claude-mount").read()
print("MOUNT_POLICY_USER", "Only remote User settings" in cm)
print("MOUNT_POLICY_FN", cm.count("_apply_git_scm_policy"))
print("LE_CR", open("/usr/local/bin/laptop-exec","rb").read().count(b"\r"))
print("VER", open("/usr/local/share/claude-client/connect-version.txt").read().strip())
sud=open("/etc/sudoers.d/claude-client-deploy").read()
print("SUDOERS_SEPIDZ", "sepidz" in sud and "NOPASSWD" in sud)
# git settings live users
import json
for u in ("farzadb","hosseinm","hosseinb"):
  p=f"/home/{u}/.cursor-server/data/User/settings.json"
  j=json.load(open(p))
  print(f"GIT_{u}", j.get("git.enabled") is False and j.get("git.repositoryScanMaxDepth")==0)
'@
[IO.File]::WriteAllText("$env:TEMP\deep_sys.py", $syspy)

$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 - <<''PY''' + $nl + $syspy + $nl + 'PY' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_all_check.py; ec1=$?' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/sepidz_io_retest.py; ec2=$?' + $nl +
  'echo remote_ec1=$ec1 remote_ec2=$ec2' + $nl +
  'exit $(( ec1 != 0 || ec2 != 0 ))' + $nl

# simpler: two python files already on remote
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' tee /tmp/deep_sys.py >/dev/null <<''ENDSYS''' + $nl + $syspy + $nl + 'ENDSYS' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_sys.py' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_all_check.py; ec1=$?' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/sepidz_io_retest.py; ec2=$?' + $nl +
  'echo remote_ec1=$ec1 remote_ec2=$ec2' + $nl +
  'if [ "$ec1" != 0 ] || [ "$ec2" != 0 ]; then exit 1; fi' + $nl

[IO.File]::WriteAllText("$env:TEMP\deep_all_wrap.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\deep_all_wrap.sh" 'sepidz@192.168.250.70:/tmp/deep_all_wrap.sh'
ssh -o BatchMode=yes -o ConnectTimeout=300 sepidz@192.168.250.70 'bash /tmp/deep_all_wrap.sh'
if ($LASTEXITCODE -ne 0) { FAIL "sepidz live deep exit=$LASTEXITCODE" } else { OK 'sepidz live deep' }

Write-Host '======== RESULT ========'
Write-Host "local_fail=$fail"
if ($fail -ne 0) { exit 1 }
Write-Host 'ALL_DEEP_GREEN'
exit 0
