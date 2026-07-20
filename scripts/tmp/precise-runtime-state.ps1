$ErrorActionPreference='Continue'
Write-Output '======== 1) ACTIVE TUNNEL PROCESS ========'
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match '-R\s+\d+:localhost:22' } |
  ForEach-Object {
    "pid=$($_.ProcessId)"
    "cmd=$($_.CommandLine)"
    try {
      $p=Get-Process -Id $_.ProcessId -EA Stop
      "start=$($p.StartTime)  cpu_s=$([math]::Round($p.CPU,1))  ws_mb=$([math]::Round($p.WorkingSet64/1MB,1))"
    } catch {}
  }

Write-Output ''
Write-Output '======== 2) CONNECT POWERSHELL / CMD PROCESSES ========'
Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object {
    $_.Name -match 'powershell|pwsh|cmd' -and $_.CommandLine -and
    ($_.CommandLine -match 'connect\.ps1|connect\.bat|Claude Connect|claude-code-client')
  } |
  ForEach-Object {
    "pid=$($_.ProcessId) name=$($_.Name)"
    "cmd=$($_.CommandLine.Substring(0,[Math]::Min(220,$_.CommandLine.Length)))"
  }

Write-Output ''
Write-Output '======== 3) CONNECT.LOG CANDIDATES (mtime desc) ========'
$cands = @()
$cands += Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Recurse -Filter 'connect.log' -EA SilentlyContinue
$cands += Get-ChildItem 'D:\Smart\Claude-Code-Server\scripts\client' -Recurse -Filter 'connect.log' -EA SilentlyContinue
$cands += Get-ChildItem "$env:USERPROFILE\Desktop" -Filter 'connect.log' -EA SilentlyContinue
$cands += Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows' -Filter 'connect.log*' -EA SilentlyContinue
$cands = $cands | Sort-Object LastWriteTime -Descending | Select-Object -Unique -First 8
foreach ($f in $cands) {
  Write-Output ("--- {0}" -f $f.FullName)
  Write-Output ("mtime={0} size={1}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff'), $f.Length)
  $vers = Select-String -Path $f.FullName -Pattern 'version=2026\d+\.\d+|ConnectVersion|ENV version=' -EA SilentlyContinue |
    Select-Object -Last 5
  foreach ($v in $vers) { "  L$($v.LineNumber): $($v.Line.Trim())" }
  $last = Get-Content $f.FullName -Tail 3 -EA SilentlyContinue
  foreach ($l in $last) { "  TAIL: $l" }
}

Write-Output ''
Write-Output '======== 4) WHERE WOULD RECONNECT LOAD FROM? ========'
# Common launchers
$launchers = @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.bat',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.ps1',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.bat',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt'
)
foreach ($p in $launchers) {
  if (Test-Path $p) {
    $i=Get-Item $p
    $extra=''
    if ($p -match 'connect-version\.txt') { $extra=' ver=' + (Get-Content $p -Raw).Trim() }
    if ($p -match 'connect\.ps1$') {
      $m=Select-String -Path $p -Pattern "ConnectVersion\s*=\s*'([^']+)'" | Select-Object -First 1
      if ($m) { $extra=" ConnectVersion=$($m.Matches[0].Groups[1].Value)" }
      $has=[bool](Select-String -Path $p -Pattern 'tunnelSyncOk' -Quiet)
      $extra += " tunnelSyncOk=$has"
    }
    if ($p -match 'git-mode\.ps1$') { }
    "EXISTS  mtime=$($i.LastWriteTime.ToString('HH:mm:ss'))  $p$extra"
  } else { "MISSING $p" }
}

# Desktop pack git-mode markers
$gm='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\git-mode.ps1'
if (Test-Path $gm) {
  Write-Output ''
  Write-Output 'Desktop pack git-mode.ps1:'
  Write-Output ("  nc-w2=" + [bool](Select-String -Path $gm -Pattern 'nc -w 2' -Quiet))
  Write-Output ("  reattach=" + [bool](Select-String -Path $gm -Pattern 'Reattach BEFORE' -Quiet))
  Write-Output ("  mtime=" + (Get-Item $gm).LastWriteTime)
}

Write-Output ''
Write-Output '======== 5) SERVER BUNDLE vs DESKTOP PACK (sha) ========'
# Compare key file hashes locally vs what we expect
$files=@('connect-version.txt','connect.ps1','git-mode.ps1','connect-diagnostic.ps1')
$desk='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
$repo='D:\Smart\Claude-Code-Server\scripts\client'
foreach ($f in $files) {
  $d=Join-Path $desk $f
  $r = if ($f -eq 'connect.ps1' -or $f -eq 'connect-version.txt') { Join-Path $repo "windows\$f" }
       elseif ($f -eq 'connect-diagnostic.ps1') { Join-Path $repo $f }
       else { Join-Path $repo $f }
  if ((Test-Path $d) -and (Test-Path $r)) {
    $hd=(Get-FileHash $d -Algorithm SHA256).Hash.Substring(0,12)
    $hr=(Get-FileHash $r -Algorithm SHA256).Hash.Substring(0,12)
    $same= if($hd -eq $hr){'SAME'} else {'DIFF'}
    "$same  $f  desk=$hd  repo=$hr"
  }
}

Write-Output ''
Write-Output '======== 6) LIVE PROBE NUMBERS (precise) ========'
$py=@'
import paramiko, re
c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.210.240", username="smart", timeout=15, allow_agent=True, look_for_keys=True)
cmd=r'''
python3 - <<'PY'
import subprocess, concurrent.futures, time
PORT=21003
def new():
    p=subprocess.run(["bash","-lc",f"timeout 3 nc -w 2 127.0.0.1 {PORT} 2>/dev/null | head -1"],capture_output=True,text=True,timeout=5)
    return (p.stdout or "").strip()
def old():
    p=subprocess.run(["bash","-lc",f"timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{PORT} 2>/dev/null && timeout 2 nc 127.0.0.1 {PORT} 2>/dev/null | head -1'"],capture_output=True,text=True,timeout=6)
    return (p.stdout or "").strip()
def classify(b):
    if b.startswith("SSH-2.0-") and "OpenSSH_for_Windows" in b: return "ok"
    if "MaxStartups" in b: return "max"
    if not b: return "empty"
    return "other:"+b[:40]
# 3 rounds parallel 12
for name,fn in [("NEW",new),("OLD",old)]:
    totals={"ok":0,"max":0,"empty":0,"other":0}
    for round in range(1,4):
        with concurrent.futures.ThreadPoolExecutor(12) as ex:
            res=list(ex.map(lambda _: fn(), range(12)))
        counts={"ok":0,"max":0,"empty":0,"other":0}
        for b in res:
            k=classify(b)
            if k.startswith("other"): counts["other"]+=1
            else: counts[k]+=1
        for k in totals: totals[k]+=counts[k]
        print(f"{name}_R{round} ok={counts['ok']} max={counts['max']} empty={counts['empty']} other={counts['other']}")
        time.sleep(0.5)
    print(f"{name}_TOTAL ok={totals['ok']}/36 max={totals['max']} empty={totals['empty']}")
PY
'''
_,o,e=c.exec_command(cmd, timeout=120)
print(o.read().decode())
c.close()
'@
Set-Content scripts\tmp\_precise_probe.py -Value $py -Encoding UTF8
python -X utf8 scripts\tmp\_precise_probe.py

Write-Output ''
Write-Output '======== 7) DROP HISTORIC IN .1 LOG (precise counts) ========'
$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
if (Test-Path $log) {
  $drops=@(Select-String -Path $log -Pattern 'connection dropped - auto reconnect')
  $recs=@(Select-String -Path $log -Pattern 'RECOVERY_BEGIN')
  $empty=@(Select-String -Path $log -Pattern 'TUNNEL_BANNER port=21003 banner=$')
  # also banner= at EOL
  $empty2=@(Select-String -Path $log -Pattern '\[DEBUG\] GITMODE: TUNNEL_BANNER port=21003 banner=\s*$')
  $okBan=@(Select-String -Path $log -Pattern 'TUNNEL_BANNER port=21003 banner=SSH-2\.0-')
  "drops=$($drops.Count) recoveries=$($recs.Count) empty_banners~$($empty2.Count) ok_banners=$($okBan.Count)"
  foreach($d in $drops){ "  DROP L$($d.LineNumber) $($d.Line.Substring(0,60))" }
  $firstVer=Select-String -Path $log -Pattern 'version=20260717\.\d+' | Select-Object -First 1
  $lastVer=Select-String -Path $log -Pattern 'version=20260717\.\d+' | Select-Object -Last 1
  "first_ver_line=$($firstVer.Line)"
  "last_ver_line=$($lastVer.Line)"
  "log_span: $((Get-Content $log -TotalCount 1))"
  $lastLine=Get-Content $log -Tail 1
  "log_end: $lastLine"
}
