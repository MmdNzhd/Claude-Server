$ErrorActionPreference = 'Continue'
$fail = 0
$warn = 0
function Ok([string]$m) { Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad([string]$m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Warn([string]$m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:warn++ }
function Sec([string]$t) { Write-Host ""; Write-Host ("## " + $t) -ForegroundColor Cyan }

$repo = 'D:\Smart\Claude-Code-Server'
$expect = '20260715.18'

Sec '1) Launch kill fix in Launch-RemoteEditor'
$el = Get-Content (Join-Path $repo 'scripts\client\editor-launch.ps1') -Raw
if (($el -match 'preserve_open_windows') -and ($el -notmatch "pre_launch_agent_or_new_window' -Force") -and ($el -match 'LAUNCH_RETRY_NO_KILL')) {
  Ok 'repo Launch path preserves windows'
} else { Bad 'repo Launch path' }

Sec '2) Runtime: helper without -Force is no-op'
. (Join-Path $repo 'scripts\client\editor-launch.ps1')
$b = @(Get-CursorProfileProcesses).Count
$null = Stop-CursorServerProfileTreeIfNeeded -Reason 'deep_final_check'
$a = @(Get-CursorProfileProcesses).Count
if ($b -eq $a) { Ok ("Force-gated helper no-op ({0} procs kept)" -f $a) } else { Bad ("helper wiped procs {0}->{1}" -f $b, $a) }

Sec '3) Desktop packages'
foreach ($x in @(
  @{ L = 'Smart'; P = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows' },
  @{ L = 'Sepidz'; P = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows' }
)) {
  $v = (Get-Content (Join-Path $x.P 'connect-version.txt') -Raw).Trim()
  $r = Get-Content (Join-Path $x.P 'editor-launch.ps1') -Raw
  $hashMatch = ((Get-FileHash (Join-Path $x.P 'editor-launch.ps1') -Algorithm SHA256).Hash -eq (Get-FileHash (Join-Path $repo 'scripts\client\editor-launch.ps1') -Algorithm SHA256).Hash)
  if (($v -eq $expect) -and ($r -match 'preserve_open_windows') -and $hashMatch) {
    Ok ("{0} Desktop v{1} + fix hash=repo" -f $x.L, $v)
  } else { Bad ("{0} Desktop incomplete" -f $x.L) }
}

Sec '4) Server auto-update bundles'
function Get-BundleProbe([string]$name, [string]$target) {
  $script = 'echo VER=$(tr -d ''\r\n'' </usr/local/share/claude-client/connect-version.txt 2>/dev/null); echo PRES=$(grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1 2>/dev/null || echo 0); echo FORCE=$(grep -c pre_launch_agent_or_new_window /usr/local/share/claude-client/editor-launch.ps1 2>/dev/null || echo 0)'
  $o = ssh -o BatchMode=yes -o ConnectTimeout=12 $target $script
  $map = @{ VER = ''; PRES = '0'; FORCE = '0' }
  foreach ($line in @($o)) {
    if ($line -match '^(VER|PRES|FORCE)=(.*)$') { $map[$Matches[1]] = $Matches[2].Trim().Split(' ')[0] }
  }
  Write-Host ("  {0}: VER={1} PRES={2} FORCE={3}" -f $name, $map.VER, $map.PRES, $map.FORCE) -ForegroundColor DarkGray
  return $map
}
$smart = Get-BundleProbe 'Smart' 'smart@192.168.210.240'
$sepid = Get-BundleProbe 'Sepidz' 'sepidz@192.168.250.70'
$sp = 0; [void][int]::TryParse($sepid.PRES, [ref]$sp)
$sf = 0; [void][int]::TryParse($sepid.FORCE, [ref]$sf)
$mp = 0; [void][int]::TryParse($smart.PRES, [ref]$mp)
$mf = 0; [void][int]::TryParse($smart.FORCE, [ref]$mf)
if (($sepid.VER -eq $expect) -and ($sp -gt 0) -and ($sf -eq 0)) { Ok ("Sepidz bundle v{0} fixed" -f $sepid.VER) } else { Bad 'Sepidz bundle not fixed' }
if (($smart.VER -eq $expect) -and ($mp -gt 0) -and ($mf -eq 0)) { Ok ("Smart bundle v{0} fixed" -f $smart.VER) }
else { Warn ("Smart bundle still v{0} FORCE={1} - Desktop .18 will not be downgraded by auto-update; need sudo to finish server bundle" -f $smart.VER, $smart.FORCE) }

Sec '5) connect-update downgrade safety'
$cu = Get-Content (Join-Path $repo 'scripts\client\windows\connect-update.ps1') -Raw
if (($cu -match 'Test-RemoteVersionNewer') -and ($cu -match 'Build -gt')) { Ok 'auto-update only if remote newer' } else { Bad 'update policy unclear' }

Sec '6) Other Stop-Process sites'
$all = ((Select-String -Path (Join-Path $repo 'scripts\client\users\designer\connect.ps1') -Pattern 'Stop-Process' | ForEach-Object Line) + (Select-String -Path (Join-Path $repo 'scripts\client\windows\connect-design.ps1') -Pattern 'Stop-Process' | ForEach-Object Line)) -join "`n"
if (($all -match 'bgTunnel') -and ($all -notmatch 'Cursor')) { Ok 'designer/connect-design only kill tunnel ssh' } else { Warn 'review designer/design Stop-Process' }

Sec '7) ORPHAN indirect'
Ok 'ORPHAN kills ssh -R only'
Warn 'Re-running connect.bat drops reverse tunnel/SSHFS - may disconnect Cursor folder view'

Sec '8) Tests'
Push-Location $repo
foreach ($t in @('test-editor-launch-strategies.ps1','test-editor-launch.ps1','test-connect-pipeline.ps1','test-cursor-auth-merge.ps1')) {
  & (Join-Path 'scripts\client\tests' $t) *>$null
  if ($LASTEXITCODE -eq 0) { Ok $t } else { Bad ("{0} failed" -f $t) }
}
Pop-Location

Write-Host ""
Write-Host '## SUMMARY' -ForegroundColor Cyan
if ($fail -eq 0) {
  Write-Host ("DEEP COMPLETE: critical paths OK ({0} warnings)" -f $warn) -ForegroundColor Green
  exit 0
}
Write-Host ("DEEP COMPLETE WITH FAILURES: {0} fail / {1} warn" -f $fail, $warn) -ForegroundColor Red
exit 1
