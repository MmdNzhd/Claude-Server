#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$repo = 'D:\Smart\Claude-Code-Server'
$smartPkg = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717'
$sepidPkg = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
$expectVer = '20260717.1'

function Sha([string]$p) {
  if (-not (Test-Path $p)) { return 'MISSING' }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.Substring(0,16)
}
function Ver([string]$p) {
  if (-not (Test-Path $p)) { return 'MISSING' }
  (Get-Content $p -Raw).Trim()
}
function Markers([string]$p) {
  if (-not (Test-Path $p)) { return @{ ok=$false } }
  $c = Get-Content $p -Raw
  @{
    ok = $true
    preserve = ([regex]::Matches($c,'preserve_open_windows')).Count
    forceMarker = ([regex]::Matches($c,'pre_launch_agent_or_new_window')).Count
    retry = ([regex]::Matches($c,'LAUNCH_RETRY_NO_KILL')).Count
    forceCalls = ([regex]::Matches($c,'Stop-CursorServerProfileTreeIfNeeded[^\r\n]*-Force')).Count
    stopTotal = ([regex]::Matches($c,'Stop-CursorServerProfileTreeIfNeeded')).Count
    hasKillSkip = $c -match 'LAUNCH_KILL_SKIP'
  }
}
function HasIp([string]$p, [string]$ip) {
  if (-not (Test-Path $p)) { return $false }
  (Get-Content $p -Raw) -match [regex]::Escape($ip)
}
function ConnectVerConst([string]$p) {
  if (-not (Test-Path $p)) { return 'MISSING' }
  $m = Select-String -Path $p -Pattern "ScriptConnectVersion\s*=\s*'([^']+)'|ConnectVersion\s*=\s*'([^']+)'|CONNECT_VERSION='([^']+)'|`$script:ConnectVersion\s*=\s*'([^']+)'" | Select-Object -First 3
  if (-not $m) {
    $m2 = Select-String -Path $p -Pattern '2026071[0-9]\.\d+' | Select-Object -First 5
    return (($m2 | ForEach-Object { $_.Line.Trim() }) -join ' || ')
  }
  return (($m | ForEach-Object { $_.Line.Trim() }) -join ' || ')
}

Write-Output '======== 1) VERSION MATRIX ========'
$rows = @(
  @{ N='REPO_win'; P="$repo\scripts\client\windows\connect-version.txt" },
  @{ N='REPO_mac'; P="$repo\scripts\client\mac\connect-version.txt" },
  @{ N='SMART_PKG_win'; P="$smartPkg\windows\connect-version.txt" },
  @{ N='SMART_PKG_mac'; P="$smartPkg\mac\connect-version.txt" },
  @{ N='SEPID_PKG_win'; P="$sepidPkg\windows\connect-version.txt" },
  @{ N='SEPID_PKG_mac'; P="$sepidPkg\mac\connect-version.txt" }
)
foreach ($r in $rows) {
  $v = Ver $r.P
  $pass = if ($v -eq $expectVer) { 'PASS' } else { 'FAIL' }
  Write-Output ("{0,-16} {1,-12} {2}" -f $r.N, $v, $pass)
}

Write-Output ''
Write-Output '======== 2) CONNECT CONSTANTS ========'
foreach ($item in @(
  @{ N='REPO connect.ps1'; P="$repo\scripts\client\windows\connect.ps1" },
  @{ N='SMART connect.ps1'; P="$smartPkg\windows\connect.ps1" },
  @{ N='SEPID connect.ps1'; P="$sepidPkg\windows\connect.ps1" },
  @{ N='REPO connect.sh'; P="$repo\scripts\client\mac\connect.sh" },
  @{ N='SMART connect.sh'; P="$smartPkg\mac\connect.sh" },
  @{ N='SEPID connect.sh'; P="$sepidPkg\mac\connect.sh" }
)) {
  Write-Output ("{0}: {1}" -f $item.N, (ConnectVerConst $item.P))
}

Write-Output ''
Write-Output '======== 3) KILL-FIX MARKERS (editor-launch) ========'
foreach ($item in @(
  @{ N='REPO'; P="$repo\scripts\client\editor-launch.ps1" },
  @{ N='SMART_PKG'; P="$smartPkg\windows\editor-launch.ps1" },
  @{ N='SEPID_PKG'; P="$sepidPkg\windows\editor-launch.ps1" }
)) {
  $m = Markers $item.P
  if (-not $m.ok) { Write-Output ("{0}: MISSING" -f $item.N); continue }
  $ok = ($m.preserve -ge 1 -and $m.forceMarker -eq 0 -and $m.retry -ge 1 -and $m.forceCalls -eq 0)
  Write-Output ("{0}: preserve={1} forceMarker={2} retry={3} forceCalls={4} stopTotal={5} killSkip={6} => {7}" -f `
    $item.N,$m.preserve,$m.forceMarker,$m.retry,$m.forceCalls,$m.stopTotal,$m.hasKillSkip,$(if($ok){'PASS'}else{'FAIL'}))
}

Write-Output ''
Write-Output '======== 4) SHA256 ALIGNMENT (critical files) ========'
$crit = @(
  @{ Rel='editor-launch.ps1'; Repo="$repo\scripts\client\editor-launch.ps1"; Smart="$smartPkg\windows\editor-launch.ps1"; Sepid="$sepidPkg\windows\editor-launch.ps1" },
  @{ Rel='connect-version.txt'; Repo="$repo\scripts\client\windows\connect-version.txt"; Smart="$smartPkg\windows\connect-version.txt"; Sepid="$sepidPkg\windows\connect-version.txt" },
  @{ Rel='connect-update.ps1'; Repo="$repo\scripts\client\windows\connect-update.ps1"; Smart="$smartPkg\windows\connect-update.ps1"; Sepid="$sepidPkg\windows\connect-update.ps1" },
  @{ Rel='git-mode.ps1'; Repo="$repo\scripts\client\git-mode.ps1"; Smart="$smartPkg\windows\git-mode.ps1"; Sepid="$sepidPkg\windows\git-mode.ps1" },
  @{ Rel='connect-ui.ps1'; Repo="$repo\scripts\client\connect-ui.ps1"; Smart="$smartPkg\windows\connect-ui.ps1"; Sepid="$sepidPkg\windows\connect-ui.ps1" }
)
foreach ($f in $crit) {
  $sr = Sha $f.Repo; $ss = Sha $f.Smart; $sz = Sha $f.Sepid
  $align = ($sr -eq $ss -and $ss -eq $sz -and $sr -ne 'MISSING')
  Write-Output ("{0,-22} repo={1} smart={2} sepid={3} => {4}" -f $f.Rel,$sr,$ss,$sz,$(if($align){'MATCH'}else{'DIFF'}))
}

Write-Output ''
Write-Output '======== 5) connect.ps1 SHA (expect Sepid DIFF due to IP) ========'
$cps = @{
  Repo = Sha "$repo\scripts\client\windows\connect.ps1"
  Smart = Sha "$smartPkg\windows\connect.ps1"
  Sepid = Sha "$sepidPkg\windows\connect.ps1"
}
Write-Output ("connect.ps1 repo={0} smart={1} sepid={2}" -f $cps.Repo,$cps.Smart,$cps.Sepid)
Write-Output ("repo==smart? {0}" -f ($cps.Repo -eq $cps.Smart))
Write-Output ("smart!=sepid (expected)? {0}" -f ($cps.Smart -ne $cps.Sepid))

Write-Output ''
Write-Output '======== 6) IP PATCH CHECK ========'
foreach ($item in @(
  @{ N='SMART connect.ps1'; P="$smartPkg\windows\connect.ps1"; Want='192.168.210.240'; Bad='192.168.250.70' },
  @{ N='SMART connect.sh'; P="$smartPkg\mac\connect.sh"; Want='192.168.210.240'; Bad='192.168.250.70' },
  @{ N='SEPID connect.ps1'; P="$sepidPkg\windows\connect.ps1"; Want='192.168.250.70'; Bad='192.168.210.240' },
  @{ N='SEPID connect.sh'; P="$sepidPkg\mac\connect.sh"; Want='192.168.250.70'; Bad='192.168.210.240' },
  @{ N='SEPID designer.ps1'; P=(Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\designer\windows\connect.ps1'); Want='192.168.250.70'; Bad='192.168.210.240' },
  @{ N='SEPID designer.sh'; P=(Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\designer\mac\connect.sh'); Want='192.168.250.70'; Bad='192.168.210.240' }
)) {
  $hasWant = HasIp $item.P $item.Want
  $hasBad = HasIp $item.P $item.Bad
  $pass = $hasWant -and -not $hasBad
  Write-Output ("{0}: want={1} bad={2} => {3}" -f $item.N,$hasWant,$hasBad,$(if($pass){'PASS'}else{'FAIL'}))
}

Write-Output ''
Write-Output '======== 7) STALE DESKTOP PACKS ========'
$desk = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $desk -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
  $wins = Get-ChildItem $_.FullName -Recurse -Filter 'connect-version.txt' -EA SilentlyContinue | Where-Object { $_.FullName -match '\\windows\\' }
  foreach ($vf in $wins) {
    $v = (Get-Content $vf.FullName -Raw).Trim()
    $el = Join-Path $vf.DirectoryName 'editor-launch.ps1'
    $fm = 'n/a'
    if (Test-Path $el) { $fm = (Markers $el).forceMarker }
    $tag = if ($v -eq $expectVer) { 'CURRENT' } elseif ($fm -eq 0) { 'OLD_BUT_FIXED' } elseif ($fm -eq 1) { 'OLD_KILL' } else { 'OLD' }
    Write-Output ("{0,-40} ver={1,-12} forceMarker={2} {3}" -f $_.Name,$v,$fm,$tag)
  }
}

Write-Output ''
Write-Output '======== 8) REMOTE SERVERS (live) ========'
function RemoteProbe($label,$target) {
  Write-Output "--- $label ($target) ---"
  $cmd = @'
set -e
B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < "$B/connect-version.txt" 2>/dev/null || echo MISSING)
echo manifest_has_editor=$(grep -c editor-launch.ps1 "$B/manifest.txt" 2>/dev/null || echo 0)
echo preserve=$(grep -c preserve_open_windows "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo forceCalls=$(grep -Ec 'Stop-CursorServerProfileTreeIfNeeded.*-Force' "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo killSkip=$(grep -c LAUNCH_KILL_SKIP "$B/editor-launch.ps1" 2>/dev/null || echo 0)
# key line excerpts
grep -nE 'preserve_open_windows|pre_launch_agent_or_new_window|LAUNCH_RETRY_NO_KILL|LAUNCH_KILL_SKIP|Stop-CursorServerProfileTreeIfNeeded' "$B/editor-launch.ps1" | head -20
echo '--- sha ---'
sha256sum "$B/connect-version.txt" "$B/editor-launch.ps1" "$B/connect.ps1" 2>/dev/null | awk '{print substr($1,1,16),$2}'
echo '--- bundle deploy dir ---'
ls -la ~/claude-client-bundle-deploy 2>/dev/null | head -8 || echo none
# unzip version inside uploaded zip if present
if [ -f ~/claude-client-bundle-deploy/bundle.zip ]; then
  python3 - <<'PY'
import zipfile,sys
z=zipfile.ZipFile('/home/'+__import__('os').environ.get('USER','smart')+'/claude-client-bundle-deploy/bundle.zip')
# try common names
for n in z.namelist():
  if n.endswith('connect-version.txt') and '/' not in n.strip('/').replace('connect-version.txt','x').rstrip('x') or n=='connect-version.txt' or n.endswith('/connect-version.txt') and n.count('/')<=1:
    if n.endswith('connect-version.txt') and not n.startswith('mac/'):
      data=z.read(n).decode('utf-8','replace').strip().replace('\r','')
      if n=='connect-version.txt' or n.endswith('/connect-version.txt') and 'mac' not in n:
        print('zip_root_version='+data+' file='+n)
        break
else:
  # fallback first connect-version.txt not under mac
  for n in z.namelist():
    if n.endswith('connect-version.txt') and '/mac/' not in n and not n.startswith('mac/'):
      print('zip_version='+z.read(n).decode('utf-8','replace').strip().replace('\r','')+' file='+n)
      break
PY
fi
'@
  # Fix home path for sepidz user in python - use simpler remote
  $cmd2 = @'
B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < "$B/connect-version.txt" 2>/dev/null || echo MISSING)
echo preserve=$(grep -c preserve_open_windows "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo forceCalls=$(grep -Ec 'Stop-CursorServerProfileTreeIfNeeded.*-Force' "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo killSkip=$(grep -c LAUNCH_KILL_SKIP "$B/editor-launch.ps1" 2>/dev/null || echo 0)
echo 'LINES:'
grep -nE 'preserve_open_windows|pre_launch_agent_or_new_window|LAUNCH_RETRY_NO_KILL|LAUNCH_KILL_SKIP|Stop-CursorServerProfileTreeIfNeeded' "$B/editor-launch.ps1" | head -20
echo 'SHA:'
sha256sum "$B/connect-version.txt" "$B/editor-launch.ps1" "$B/connect.ps1" 2>/dev/null | awk '{print substr($1,1,16),$2}'
echo 'ZIP:'
if [ -f "$HOME/claude-client-bundle-deploy/bundle.zip" ]; then
  python3 -c "import zipfile; z=zipfile.ZipFile('$HOME/claude-client-bundle-deploy/bundle.zip');
names=[n for n in z.namelist() if n.endswith('connect-version.txt')];
print('zip_entries',names);
root=[n for n in names if n=='connect-version.txt' or n.count('/')==0];
pick=root[0] if root else ([n for n in names if not n.startswith('mac/')][:1] or names)[0];
print('zip_ver='+z.read(pick).decode().strip().replace(chr(13),'')+' from='+pick)"
  ls -la "$HOME/claude-client-bundle-deploy/bundle.zip"
else
  echo 'no_local_zip'
fi
echo 'MANIFEST_HEAD:'
head -20 "$B/manifest.txt" 2>/dev/null || echo no_manifest
# IP inside installed connect.ps1
echo -n 'connect_ip_smart240='; grep -c '192.168.210.240' "$B/connect.ps1" 2>/dev/null || echo 0
echo -n 'connect_ip_sepid70='; grep -c '192.168.250.70' "$B/connect.ps1" 2>/dev/null || echo 0
'@
  $a = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=12','-o','StrictHostKeyChecking=accept-new',$target,$cmd2)
  $out = Join-Path $env:TEMP ("deep-$label.out")
  $err = Join-Path $env:TEMP ("deep-$label.err")
  $p = Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(25000)) { try{$p.Kill()}catch{}; Write-Output 'TIMEOUT'; return }
  Write-Output ("exit=" + $p.ExitCode)
  Get-Content $out -EA SilentlyContinue
  $e = Get-Content $err -EA SilentlyContinue
  if ($e) { Write-Output 'STDERR:'; $e | Select-Object -First 15 }
}

RemoteProbe 'SMART' 'smart@192.168.210.240'
RemoteProbe 'SEPIDZ' 'sepidz@192.168.250.70'

Write-Output ''
Write-Output '======== 9) DEPLOY SCRIPT FALSE-OK BUG ========'
$dep = Join-Path $repo 'publish\deploy-client-bundles.ps1'
if (Test-Path $dep) {
  # show verification logic
  Select-String -Path $dep -Pattern 'remoteVer|Write-DeployOk|Timed out|sudo password|Test-Remote|expected' |
    Select-Object -First 40 |
    ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
  Write-Output '---'
  # Does it compare deployed version to local package version?
  $raw = Get-Content $dep -Raw
  $compares = $raw -match 'remoteVer\s*-eq|remoteVer\s*-ne|expectedVer|packageVer|localVer'
  Write-Output ("compares_remote_to_expected=" + [bool]$compares)
  Write-Output ("has_Get-SmartSudoPassword=" + ($raw -match 'Get-SmartSudoPassword'))
  Write-Output ("has_Get-SepidzSudoPassword=" + ($raw -match 'Get-SepidzSudoPassword'))
} else { Write-Output 'deploy script MISSING' }

Write-Output ''
Write-Output '======== 10) connect-update NEWER LOGIC ========'
$up = "$smartPkg\windows\connect-update.ps1"
if (Test-Path $up) {
  Select-String -Path $up -Pattern 'Test-RemoteVersionNewer|Remote -gt|return' |
    Select-Object -First 25 |
    ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
}

Write-Output ''
Write-Output '======== 11) VERDICT ========'
Write-Output "Expected version: $expectVer"
