Set-Location D:\Smart\Claude-Code-Server
$ErrorActionPreference='Continue'
$ver = (Get-Content scripts/client/windows/connect-version.txt -Raw).Trim()
Write-Host "REPO_VER=$ver"

# parse critical
$bad=$false
foreach ($rel in @('scripts/client/windows/connect.ps1','scripts/client/connect-ui.ps1','scripts/client/git-mode.ps1','scripts/client/editor-launch.ps1')) {
  $tok=$null;$err=$null
  $null=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $rel),[ref]$tok,[ref]$err)
  if ($err -and $err.Count) {
    Write-Host "PARSE_FAIL $rel" -ForegroundColor Red
    $err | ForEach-Object { Write-Host ("  " + $_.Message) }
    $bad=$true
  } else { Write-Host "PARSE_OK $rel" -ForegroundColor Green }
}

$ui = Get-Content scripts/client/connect-ui.ps1 -Raw
$win = Get-Content scripts/client/windows/connect.ps1 -Raw
$gm = Get-Content scripts/client/git-mode.ps1 -Raw

# markers from late agents
$checks = @(
  @{n='empty_exit decision'; c={ $win -match 'empty_exit|ssh_username_fix' }},
  @{n='heartbeat throttle'; c={ $ui -match 'LastHeartbeatUnix|60' }},
  @{n='Initialize-ConnectProxyForSsh'; c={ $ui -match 'Initialize-ConnectProxyForSsh' }},
  @{n='StopEditor opt-in'; c={ $gm -match '\[switch\]\$StopEditor' -and $gm -match 'if \(\$StopEditor' }},
  @{n='TunnelPid'; c={ $gm -match '\[int\]\$TunnelPid' }},
  @{n='no doubled ConnectVersion'; c={ $win -notmatch 'ConnectVersion\$script:ConnectVersion' -and ($win -match "(?m)^\`$script:ConnectVersion = '$([regex]::Escape($ver))'\s*$") }},
  @{n='path_scoped stop'; c={ (Get-Content scripts/client/editor-launch.ps1 -Raw) -match 'path_scoped' }}
)
foreach ($ch in $checks) {
  $ok = & $ch.c
  Write-Host ("{0} {1}" -f ($(if($ok){'PASS'}else{'MISS'}), $ch.n)) -ForegroundColor $(if($ok){'Green'}else{'Yellow'})
}

# compare pack hash of key files vs repo
$pack = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260720\windows'
$pver = if (Test-Path "$pack\connect-version.txt") { (Get-Content "$pack\connect-version.txt" -Raw).Trim() } else { 'MISSING' }
Write-Host "PACK_VER=$pver"
$needRepublish = $false
foreach ($f in @('connect.ps1','connect-ui.ps1','git-mode.ps1','editor-launch.ps1')) {
  $a = (Get-FileHash "scripts/client$(if($f -eq 'connect.ps1'){'\windows'}else{''})\$f" -Algorithm SHA256).Hash
  # map paths
}
# explicit paths
$map = @(
  @{r='scripts/client/windows/connect.ps1'; p="$pack\connect.ps1"},
  @{r='scripts/client/connect-ui.ps1'; p="$pack\connect-ui.ps1"},
  @{r='scripts/client/git-mode.ps1'; p="$pack\git-mode.ps1"},
  @{r='scripts/client/editor-launch.ps1'; p="$pack\editor-launch.ps1"}
)
foreach ($m in $map) {
  if (-not (Test-Path $m.p)) { Write-Host "MISSING pack $($m.p)"; $needRepublish=$true; continue }
  $hr = (Get-FileHash $m.r -Algorithm SHA256).Hash
  $hp = (Get-FileHash $m.p -Algorithm SHA256).Hash
  $same = $hr -eq $hp
  Write-Host ("{0} {1}" -f ($(if($same){'SAME'}else{'DIFF'}), [IO.Path]::GetFileName($m.r))) -ForegroundColor $(if($same){'Green'}else{'Yellow'})
  if (-not $same) { $needRepublish = $true }
}
if ($bad) { Write-Host 'NEED_FIX_PARSE'; exit 2 }
if ($needRepublish) { Write-Host 'NEED_REPUBLISH'; exit 3 }
Write-Host 'IN_SYNC'
exit 0
