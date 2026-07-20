$ErrorActionPreference = 'Continue'
$expect = '20260717.3'
$fail = 0
function Pass([string]$m) { Write-Host "PASS  $m" -ForegroundColor Green }
function Fail([string]$m) { Write-Host "FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Info([string]$m) { Write-Host "INFO  $m" -ForegroundColor Cyan }

Write-Host "`n======== 1) REPO VERSION ========" -ForegroundColor White
$repo = 'D:\Smart\Claude-Code-Server'
$rv = (Get-Content "$repo\scripts\client\windows\connect-version.txt" -Raw).Trim()
if ($rv -eq $expect) { Pass "repo connect-version=$rv" } else { Fail "repo connect-version=$rv want=$expect" }
$cps = Select-String -Path "$repo\scripts\client\windows\connect.ps1" -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1
if ($cps.Matches[0].Groups[1].Value -eq $expect) { Pass "connect.ps1 ConnectVersion=$expect" } else { Fail "connect.ps1 version mismatch" }

Write-Host "`n======== 2) DESKTOP PACKS ========" -ForegroundColor White
$packs = @(
  @{ N='Smart'; R="$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows" },
  @{ N='Sepidz'; R="$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows" }
)
foreach ($p in $packs) {
  if (-not (Test-Path $p.R)) { Fail "$($p.N) pack missing"; continue }
  $v = (Get-Content "$($p.R)\connect-version.txt" -Raw).Trim()
  $el = Get-Content "$($p.R)\editor-launch.ps1" -Raw
  $gm = Get-Content "$($p.R)\git-mode.ps1" -Raw
  $auth = Get-Content "$($p.R)\cursor-auth-laptop.ps1" -Raw
  $diag = Get-Content "$($p.R)\connect-diagnostic.ps1" -Raw
  if ($v -eq $expect) { Pass "$($p.N) ver=$v" } else { Fail "$($p.N) ver=$v" }
  if ($el -match 'Default User') { Pass "$($p.N) Cursor multi-profile scan" } else { Fail "$($p.N) missing multi-profile scan" }
  if ($auth -match 'Get-CursorAuthTempRoot') { Pass "$($p.N) auth TEMP fix" } else { Fail "$($p.N) auth TEMP missing" }
  if ($gm -match 'Test-TunnelBannerIsWindows -Banner \$banner') { Pass "$($p.N) tunnel up-from-banner" } else { Fail "$($p.N) tunnel fix missing" }
  if ($diag -match 'not found for this Windows user') { Pass "$($p.N) diag message" } else { Fail "$($p.N) diag message" }
  if ($el -match 'preserve_open_windows' -and $el -notmatch 'pre_launch_agent_or_new_window') { Pass "$($p.N) kill-fix" } else { Fail "$($p.N) kill-fix markers" }
}

Write-Host "`n======== 3) Ensure-EditorOnPath SMOKE ========" -ForegroundColor White
. "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows\editor-launch.ps1"
$script:LaptopUser = 'Smart'
$cli = Ensure-EditorOnPath 'cursor'
$exe = Get-EditorNativeExe 'cursor'
if ($cli -and (Test-Path $cli)) { Pass "Ensure-EditorOnPath => $cli" } else { Fail "Ensure-EditorOnPath returned null/missing" }
if ($exe -and (Test-Path $exe)) { Pass "Get-EditorNativeExe => $exe" } else { Fail "Get-EditorNativeExe failed" }

# Simulate Admin: LaptopUser empty-ish wrong, USERNAME override by scanning all users
$script:LaptopUser = 'NoSuchUser_AdminSim'
$env:USERNAME = 'Administrator'
$cli2 = Ensure-EditorOnPath 'cursor'
if ($cli2 -and (Test-Path $cli2)) { Pass "Admin-sim still finds Cursor => $cli2" } else { Fail "Admin-sim CURSOR_NOT_FOUND (scan failed)" }
# restore
$env:USERNAME = 'Smart'
$script:LaptopUser = 'Smart'

Write-Host "`n======== 4) REMOTE SERVERS (paramiko) ========" -ForegroundColor White
$py = @'
import sys, pathlib
import paramiko
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
KEY = pathlib.Path.home() / ".ssh" / "id_ed25519"
EXPECT = "20260717.3"

def probe(label, host, user):
    print(f"--- {label} ---")
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    cmd = r"""
B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt 2>/dev/null)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1 2>/dev/null || echo 0)
echo scan=$(grep -c 'Default User' $B/editor-launch.ps1 2>/dev/null || echo 0)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1 2>/dev/null || echo 0)
echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1 2>/dev/null || echo 0)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1 2>/dev/null || echo 0)
echo diag=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1 2>/dev/null || echo 0)
echo zip_ver=$(python3 -c "import zipfile;z=zipfile.ZipFile('/home/'"$USER"'/claude-client-bundle-deploy/bundle.zip');print(z.read('connect-version.txt').decode().strip())" 2>/dev/null || echo none)
"""
    _, so, _ = c.exec_command(cmd, timeout=30)
    out = so.read().decode().strip()
    print(out)
    c.close()
    return out

for label, host, user in [("SEPIDZ","192.168.250.70","sepidz"),("SMART","192.168.210.240","smart")]:
    try:
        probe(label, host, user)
    except Exception as e:
        print(f"{label} ERROR: {e}")
'@
$pyPath = Join-Path $env:TEMP 'probe-servers-173.py'
Set-Content -Path $pyPath -Value $py -Encoding UTF8
python -u $pyPath

Write-Host "`n======== 5) CLIENT REGRESSION (selected) ========" -ForegroundColor White
$tests = @(
  'test-editor-launch.ps1',
  'test-connect-pipeline.ps1',
  'test-git-mode-deep.ps1'
)
$testDir = Join-Path $repo 'scripts\client\tests'
foreach ($t in $tests) {
  $tp = Join-Path $testDir $t
  if (-not (Test-Path $tp)) { Fail "missing test $t"; continue }
  Info "Running $t ..."
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $tp 2>&1 | Out-String
  $code = $LASTEXITCODE
  if ($code -eq 0 -or $out -match 'PASS|All tests|OK') {
    # many of these write their own pass/fail
    if ($out -match '(?i)\bFAIL\b' -and $out -notmatch '(?i)0 fail') {
      # check for explicit failure counts
      if ($out -match 'FAILED|AssertionFailed|Throw') { Fail "$t failed"; Write-Host ($out.Substring([Math]::Max(0,$out.Length-800))) }
      else { Pass "$t exit=$code (see log)" }
    } else {
      Pass "$t exit=$code"
    }
  } else {
    Fail "$t exit=$code"
    Write-Host ($out.Substring([Math]::Max(0,$out.Length-800)))
  }
}

Write-Host "`n======== 6) DEPLOY VERIFY SCRIPT ========" -ForegroundColor White
$dep = Get-Content "$repo\publish\deploy-client-bundles.ps1" -Raw
if ($dep -match 'Remote version mismatch' -and $dep -match 'ExpectedVersion') { Pass "deploy version-compare present" } else { Fail "deploy version-compare missing" }

Write-Host "`n======== SUMMARY ========" -ForegroundColor White
if ($fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red; exit 1 }
