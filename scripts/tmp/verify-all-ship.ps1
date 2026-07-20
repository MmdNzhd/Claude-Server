$ErrorActionPreference='Continue'
$Expected='20260717.5'
$fail=0
function Pass($m){ Write-Host "PASS  $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL  $m" -ForegroundColor Red; $script:fail++ }

Write-Host '======== 1) REPO ========' -ForegroundColor Cyan
$repoVer=(Get-Content 'scripts\client\windows\connect-version.txt' -Raw).Trim().TrimStart([char]0xFEFF)
if($repoVer -eq $Expected){ Pass "repo version=$repoVer" } else { Fail "repo version=$repoVer expected=$Expected" }
$repoChecks=@(
  @{f='scripts\client\git-mode.ps1'; p='nc -w 2 127.0.0.1 \$Port'; n='ps1 nc-only'},
  @{f='scripts\client\git-mode.ps1'; p='banner_miss_tcp_open'; n='ps1 soft-tcp'},
  @{f='scripts\client\git-mode.ps1'; p='Reattach BEFORE'; n='ps1 reattach'},
  @{f='scripts\client\git-mode.ps1'; p='Positive cache only'; n='ps1 pos-cache'},
  @{f='scripts\client\git-mode.ps1'; p='timeout 2 nc 127.0.0.1 \$Port'; n='ps1 NO double-nc'; neg=$true},
  @{f='scripts\client\windows\connect.ps1'; p='tunnelSyncOk'; n='ps1 tunnelSyncOk'},
  @{f='scripts\client\windows\connect.ps1'; p="ConnectVersion = '$Expected'"; n='ps1 ConnectVersion'},
  @{f='scripts\client\connect-diagnostic.ps1'; p='tunnelEffectivelyUp'; n='diag effectively'},
  @{f='scripts\client\git-mode.sh'; p='nc -w 2 127.0.0.1 \${PORT}'; n='sh nc-only'},
  @{f='scripts\client\git-mode.sh'; p='banner_miss_tcp_open'; n='sh soft-tcp'},
  @{f='scripts\client\mac\connect.sh'; p="CONNECT_VERSION='$Expected'"; n='mac CONNECT_VERSION'},
  @{f='publish\deploy-client-bundles.ps1'; p='Prefer password path'; n='deploy skip sudo-n'}
)
foreach($c in $repoChecks){
  $hit=[bool](Select-String -Path $c.f -Pattern $c.p -Quiet -ErrorAction SilentlyContinue)
  if($c.neg){ if($hit){ Fail $c.n } else { Pass $c.n } }
  else { if($hit){ Pass $c.n } else { Fail $c.n } }
}

Write-Host ''
Write-Host '======== 2) DESKTOP PACKS ========' -ForegroundColor Cyan
$smart='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717'
$sepid='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
foreach($pair in @(
  @{l='SmartPack'; root=$smart},
  @{l='SepidPack'; root=$sepid}
)){
  $root=$pair.root
  if(-not (Test-Path $root)){ Fail "$($pair.l) missing $root"; continue }
  $v=(Get-Content (Join-Path $root 'windows\connect-version.txt') -Raw).Trim().TrimStart([char]0xFEFF)
  if($v -eq $Expected){ Pass "$($pair.l) version=$v" } else { Fail "$($pair.l) version=$v" }
  $gm=Join-Path $root 'windows\git-mode.ps1'
  $cp=Join-Path $root 'windows\connect.ps1'
  $dg=Join-Path $root 'windows\connect-diagnostic.ps1'
  foreach($x in @(
    @{f=$gm; p='nc -w 2'; n="$($pair.l) nc"},
    @{f=$gm; p='banner_miss_tcp_open'; n="$($pair.l) soft"},
    @{f=$gm; p='Reattach BEFORE'; n="$($pair.l) reattach"},
    @{f=$cp; p='tunnelSyncOk'; n="$($pair.l) syncOk"},
    @{f=$cp; p="ConnectVersion = '$Expected'"; n="$($pair.l) ConnectVersion"},
    @{f=$dg; p='tunnelEffectivelyUp'; n="$($pair.l) diag"}
  )){
    if(Select-String -Path $x.f -Pattern $x.p -Quiet){ Pass $x.n } else { Fail $x.n }
  }
  # Sepid IP patch
  if($pair.l -eq 'SepidPack'){
    $txt=Get-Content $cp -Raw
    if($txt -match '192\.168\.250\.70'){ Pass 'SepidPack IP patched 250.70' } else { Fail 'SepidPack IP not patched' }
    if($txt -match '192\.168\.210\.240'){ Fail 'SepidPack still has Smart IP' } else { Pass 'SepidPack no Smart IP' }
  }
}
foreach($z in @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717.zip',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717.zip'
)){
  if(Test-Path $z){ Pass "zip exists $(Split-Path $z -Leaf) size=$((Get-Item $z).Length)" } else { Fail "zip missing $z" }
}

Write-Host ''
Write-Host '======== 3) LIVE SERVERS (paramiko) ========' -ForegroundColor Cyan
$py = @'
import os, re, sys
from pathlib import Path
import paramiko
ROOT=Path(r"D:\Smart\Claude-Code-Server")
EXPECTED="20260717.5"

def pw(file, name):
    p=ROOT/"publish"/file
    t=p.read_text(encoding="utf-8", errors="replace")
    m=re.search(rf"{name}\s*=\s*'([^']*)'", t)
    return m.group(1) if m else None

def check(label, host, user):
    c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, timeout=15, allow_agent=True, look_for_keys=True)
    def run(cmd):
        _,o,e=c.exec_command(cmd, timeout=30)
        return o.read().decode("utf-8","replace").strip().lstrip("\ufeff")
    ver=run("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    print(f"VER|{label}|{ver}")
    checks={
      "banner_miss": run("grep -c banner_miss_tcp_open /usr/local/share/claude-client/git-mode.ps1 || true"),
      "nc_w2": run("grep -c 'nc -w 2' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "reattach": run("grep -c 'Reattach BEFORE' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "pos_cache": run("grep -c 'Positive cache only' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "double_nc": run("grep -c 'timeout 2 nc 127.0.0.1' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "syncOk": run("grep -c tunnelSyncOk /usr/local/share/claude-client/connect.ps1 || true"),
      "diag": run("grep -c tunnelEffectivelyUp /usr/local/share/claude-client/connect-diagnostic.ps1 || true"),
      "ver_in_ps1": run(f"grep -c \"ConnectVersion = '{EXPECTED}'\" /usr/local/share/claude-client/connect.ps1 || true"),
    }
    for k,v in checks.items():
        print(f"M|{label}|{k}|{v}")
    # live banner probe on server (single nc) — only meaningful on Smart where THIS laptop tunnel is
    if label=="Smart":
        banner=run("timeout 3 nc -w 2 127.0.0.1 21003 2>/dev/null | head -1 | tr -d '\\r'")
        print(f"PROBE|{label}|{banner}")
        sshok=run("timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/claude_laptop -p 21003 Smart@127.0.0.1 echo SSH_OK 2>/dev/null | tail -1")
        print(f"SSHOK|{label}|{sshok}")
    c.close()

check("Smart","192.168.210.240","smart")
user=None
t=(ROOT/"publish"/"sepidz-deploy.local.ps1").read_text(encoding="utf-8",errors="replace")
m=re.search(r"SepidzSshUser\s*=\s*'([^']*)'", t)
user=m.group(1) if m else "sepidz"
check("Sepidz","192.168.250.70", user)
print("PY_DONE")
'@
$pyPath = 'scripts\tmp\_verify_servers.py'
Set-Content -Path $pyPath -Value $py -Encoding UTF8
$out = & python -X utf8 $pyPath 2>&1
$out | ForEach-Object { "$_" }
foreach($line in $out){
  $s=[string]$line
  if($s -match '^VER\|([^|]+)\|(.+)$'){
    $lab=$matches[1]; $ver=$matches[2].Trim()
    if($ver -eq $Expected){ Pass "$lab remote version=$ver" } else { Fail "$lab remote version=$ver" }
  }
  elseif($s -match '^M\|([^|]+)\|([^|]+)\|(.+)$'){
    $lab=$matches[1]; $k=$matches[2]; $v=$matches[3].Trim()
    if($k -eq 'double_nc'){
      if($v -eq '0'){ Pass "$lab no-double-nc" } else { Fail "$lab still has double-nc count=$v" }
    } else {
      if([int]$v -gt 0){ Pass "$lab $k=$v" } else { Fail "$lab $k=$v" }
    }
  }
  elseif($s -match '^PROBE\|Smart\|(.+)$'){
    $b=$matches[1].Trim()
    if($b -match 'OpenSSH_for_Windows'){ Pass "Smart live banner=$b" } else { Fail "Smart live banner=[$b]" }
  }
  elseif($s -match '^SSHOK\|Smart\|(.+)$'){
    $b=$matches[1].Trim()
    if($b -eq 'SSH_OK'){ Pass 'Smart reverse SSH works' } else { Fail "Smart reverse SSH=[$b]" }
  }
}

Write-Host ''
Write-Host '======== SUMMARY ========' -ForegroundColor Cyan
if($fail -eq 0){ Write-Host "ALL_SURE fail=0" -ForegroundColor Green; exit 0 }
else { Write-Host "NOT_SURE fail=$fail" -ForegroundColor Red; exit 1 }
