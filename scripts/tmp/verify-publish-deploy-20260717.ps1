$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'

function Count-Markers([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  $c = Get-Content $path -Raw
  [pscustomobject]@{
    preserve = ([regex]::Matches($c, 'preserve_open_windows')).Count
    forceMarker = ([regex]::Matches($c, 'pre_launch_agent_or_new_window')).Count
    retryNoKill = ([regex]::Matches($c, 'LAUNCH_RETRY_NO_KILL')).Count
    forceCalls = ([regex]::Matches($c, 'Stop-CursorServerProfileTreeIfNeeded[^\r\n]*-Force')).Count
  }
}

function Show-Local([string]$label, [string]$root) {
  Write-Output "=== LOCAL_$label ==="
  if (-not (Test-Path $root)) { Write-Output "MISS $root"; return }
  $winVer = Join-Path $root 'windows\connect-version.txt'
  $macVer = Join-Path $root 'mac\connect-version.txt'
  $el = Join-Path $root 'windows\editor-launch.ps1'
  if (Test-Path $winVer) { Write-Output ("win_ver=" + ((Get-Content $winVer -Raw).Trim())) } else { Write-Output 'win_ver=MISS' }
  if (Test-Path $macVer) { Write-Output ("mac_ver=" + ((Get-Content $macVer -Raw).Trim())) } else { Write-Output 'mac_ver=MISS' }
  $m = Count-Markers $el
  if ($m) {
    Write-Output ("editor preserve=$($m.preserve) forceMarker=$($m.forceMarker) retryNoKill=$($m.retryNoKill) forceCalls=$($m.forceCalls)")
  } else {
    Write-Output 'editor=MISS'
  }
}

function Probe-Remote([string]$label, [string]$target) {
  Write-Output "=== REMOTE_$label ==="
  $cmd = @'
echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING)
EL=/usr/local/share/claude-client/editor-launch.ps1
echo preserve=$(grep -c preserve_open_windows "$EL" 2>/dev/null || echo 0)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window "$EL" 2>/dev/null || echo 0)
echo retryNoKill=$(grep -c LAUNCH_RETRY_NO_KILL "$EL" 2>/dev/null || echo 0)
echo forceCalls=$(grep -Ec "Stop-CursorServerProfileTreeIfNeeded.*-Force" "$EL" 2>/dev/null || echo 0)
ls -la ~/claude-client-bundle-deploy 2>/dev/null | sed -n "1,8p" || true
'@
  $a = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=accept-new',$target,$cmd)
  $out = Join-Path $env:TEMP ("v17-$label.out")
  $err = Join-Path $env:TEMP ("v17-$label.err")
  $p = Start-Process -FilePath ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch {}; Write-Output 'TIMEOUT'; return }
  Write-Output ("exit=" + $p.ExitCode)
  if (Test-Path $out) { Get-Content $out }
  if (Test-Path $err) {
    $e = Get-Content $err
    if ($e) { Write-Output 'STDERR:'; $e }
  }
}

Show-Local 'SMART_PKG' (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717')
Show-Local 'SEPIDZ_PKG' (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code')
Show-Local 'REPO' 'D:\Smart\Claude-Code-Server\scripts\client'
# repo versions live under windows/mac; editor-launch at scripts/client
Write-Output '=== REPO_VERSIONS ==='
foreach ($p in @(
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt',
  'D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt'
)) {
  if (Test-Path $p) { Write-Output (((Get-Content $p -Raw).Trim()) + ' | ' + $p) }
}
$repoEl = Count-Markers 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
if ($repoEl) {
  Write-Output ("repo_editor preserve=$($repoEl.preserve) forceMarker=$($repoEl.forceMarker) retryNoKill=$($repoEl.retryNoKill) forceCalls=$($repoEl.forceCalls)")
}

Probe-Remote 'SMART' 'smart@192.168.210.240'
Probe-Remote 'SEPIDZ' 'sepidz@192.168.250.70'
