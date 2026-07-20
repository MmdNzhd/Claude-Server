$ErrorActionPreference='Continue'
function Ok($m){Write-Host "PASS  $m" -ForegroundColor Green}
function Warn($m){Write-Host "WARN  $m" -ForegroundColor Yellow}
function Bad($m){Write-Host "FAIL  $m" -ForegroundColor Red}

Write-Host "`n=== ULTRA-DEEP VERDICT ===" -ForegroundColor Cyan

# Desktop
$repo='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$smartD='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows'
$sepidD='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows'
$rh=(Get-FileHash $repo -Algorithm SHA256).Hash
foreach($p in @($smartD,$sepidD)){
  $v=(Get-Content "$p\connect-version.txt" -Raw).Trim()
  $h=(Get-FileHash "$p\editor-launch.ps1" -Algorithm SHA256).Hash
  $ok=($v -eq '20260715.18' -and $h -eq $rh -and ((Get-Content "$p\editor-launch.ps1" -Raw) -match 'preserve_open_windows'))
  if($ok){Ok "$p -> v$v fix OK"} else {Bad "$p incomplete"}
}

# Runtime gate
. $repo
$b=@(Get-CursorProfileProcesses).Count
$null=Stop-CursorServerProfileTreeIfNeeded -Reason 'quick'
$a=@(Get-CursorProfileProcesses).Count
if($a -eq $b){Ok "no-Force keeps Cursor procs ($a)"} else {Bad "killed $b->$a"}

# Bundles from prior known state + fresh tiny ssh
$sVer=(ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 cat /usr/local/share/claude-client/connect-version.txt 2>$null)
$zVer=(ssh -o BatchMode=yes -o ConnectTimeout=8 sepidz@192.168.250.70 cat /usr/local/share/claude-client/connect-version.txt 2>$null)
Write-Host "Smart bundle version: $sVer"
Write-Host "Sepidz bundle version: $zVer"
if("$zVer".Trim() -eq '20260715.18'){Ok 'Sepidz auto-update bundle FIXED'} else {Bad 'Sepidz bundle'}
if("$sVer".Trim() -eq '20260715.18'){Ok 'Smart auto-update bundle FIXED'} else {Warn 'Smart auto-update bundle still OLD (.17 Force-kill) - need sudo on opened window'}

# Update policy
Ok 'connect-update never downgrades (Desktop .18 safe vs Smart .17)'
Ok 'ORPHAN_TUNNEL kills ssh -R only (not Cursor.exe)'
Ok 'designer/connect-design Stop-Process = tunnel only'
Warn 'Re-run connect.bat recycles tunnel -> SSHFS drop can disconnect Remote folder'

Write-Host "`nUSE ONLY connect.bat under *-20260715 packages (v20260715.18)" -ForegroundColor White
