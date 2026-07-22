$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

function Set-Text([string]$Path, [scriptblock]$Mutator) {
  $raw = [IO.File]::ReadAllText($Path)
  $new = & $Mutator $raw
  if ($null -eq $new) { throw "mutator returned null for $Path" }
  if ($new -eq $raw) { Write-Host "NOCHANGE $Path"; return $false }
  [IO.File]::WriteAllText($Path, $new, [Text.UTF8Encoding]::new($false))
  Write-Host "CHANGED $Path"
  return $true
}

# 1) connect.ps1: after tunnel recovery, NEVER AuthRelaunch-launch if profile windows already exist.
#    Auth merge is enough; AuthRelaunch historically soft-stopped the whole profile tree.
$conn = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($conn)
$old = @'
            $didLaunch = $false
            $launchOk = $false
            if ($authRelaunch -or (-not $editorOpened -and -not $onCorrectFolder)) {
                if ($authRelaunch -and $onCorrectFolder) {
                    Step "Reloading $EditorName (auth refresh)"
                    Write-ConnectLog 'EDITOR_LAUNCH auth_relaunch despite already_on_folder' 'INFO'
                } elseif (-not $editorOpened) {
                    Step "Opening $EditorName"
                }
                if ($authRelaunch -or -not $editorOpened) {
                    $launchOk = [bool](Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -AuthRelaunch:$authRelaunch -KnownOnFolder:$onCorrectFolder)
'@
$new = @'
            $didLaunch = $false
            $launchOk = $false
            # Tunnel recovery used to set force_auth → AuthRelaunch → soft-stop of ALL
            # ClaudeServerCursorProfile windows (profile_count=14..24). Auth merges in-place;
            # if any profile window is already open, skip relaunch entirely (VPN/tunnel flap safe).
            $profileAlreadyOpen = $false
            if ($authRelaunch -and $EditorCmd -eq 'cursor' -and (Get-Command Get-CursorProfileProcesses -ErrorAction SilentlyContinue)) {
                try { $profileAlreadyOpen = (@(Get-CursorProfileProcesses).Count -gt 0) } catch { $profileAlreadyOpen = $false }
            }
            if ($authRelaunch -and $profileAlreadyOpen) {
                Write-ConnectLog 'EDITOR_LAUNCH skip_auth_relaunch reason=profile_windows_open_preserve_after_tunnel_recovery' 'WARN'
                if ($onCorrectFolder) {
                    $launchOk = $true
                }
            }
            if ((-not $profileAlreadyOpen) -and ($authRelaunch -or (-not $editorOpened -and -not $onCorrectFolder))) {
                if ($authRelaunch -and $onCorrectFolder) {
                    Step "Reloading $EditorName (auth refresh)"
                    Write-ConnectLog 'EDITOR_LAUNCH auth_relaunch despite already_on_folder' 'INFO'
                } elseif (-not $editorOpened) {
                    Step "Opening $EditorName"
                }
                if ($authRelaunch -or -not $editorOpened) {
                    $launchOk = [bool](Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -AuthRelaunch:$authRelaunch -KnownOnFolder:$onCorrectFolder)
'@
if ($c -notlike "*$($old.Substring(0,[Math]::Min(80,$old.Length)))*") {
  # fallback: search unique marker
  if ($c -notmatch 'EDITOR_LAUNCH auth_relaunch despite already_on_folder') { throw 'connect.ps1 marker not found' }
}
if (-not $c.Contains($old)) { throw 'connect.ps1 exact block not found - abort' }
$c2 = $c.Replace($old, $new)
# bump version .49 -> .50
$c2 = $c2 -replace "ConnectVersion = '20260721\.49'", "ConnectVersion = '20260721.50'"
[IO.File]::WriteAllText($conn, $c2, [Text.UTF8Encoding]::new($false))
Write-Host 'CHANGED connect.ps1'

# 2) version files
$verFiles = @(
  'scripts\client\windows\connect-version.txt',
  'scripts\client\mac\connect-version.txt'
)
foreach ($vf in $verFiles) {
  $p = Join-Path $root $vf
  if (Test-Path $p) {
    [IO.File]::WriteAllText($p, "20260721.50`n", [Text.UTF8Encoding]::new($false))
    Write-Host "VER $vf -> 20260721.50"
  }
}
$mac = Join-Path $root 'scripts\client\mac\connect.sh'
if (Test-Path $mac) {
  $m = [IO.File]::ReadAllText($mac)
  $m2 = $m -replace "CONNECT_VERSION='20260721\.[0-9]+'", "CONNECT_VERSION='20260721.50'"
  if ($m2 -ne $m) { [IO.File]::WriteAllText($mac, $m2, [Text.UTF8Encoding]::new($false)); Write-Host 'CHANGED mac connect.sh version' }
}

# 3) editor-launch: also skip Stop-CursorServerProfileTreeIfNeeded for ANY reason containing auth
$el = Join-Path $root 'scripts\client\editor-launch.ps1'
$e = [IO.File]::ReadAllText($el)
if ($e -notmatch 'auth_relaunch_never_kill') { throw 'editor-launch missing never_kill - unexpected' }
# Harden Stop-CursorServerProfileTreeIfNeeded: refuse kill when Reason matches auth*
$oldStop = @'
function Stop-CursorServerProfileTreeIfNeeded {
'@
# Find function and inject hard refuse for auth reasons at top of body after param
if ($e -match '(?s)(function Stop-CursorServerProfileTreeIfNeeded \{.*?param\([^\)]*\)\s*)') {
  $inject = @'
function Stop-CursorServerProfileTreeIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [switch]$Force
    )
    # Hard refuse: auth / proxy / tunnel recovery must never wipe shared profile windows.
    if ($Reason -match 'auth|proxy|recovery') {
        $n = @(Get-CursorProfileProcesses).Count
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=hard_refuse_$Reason profile_count=$n force=$Force") 'WARN'
        return
    }
'@
  # Only replace if not already hard_refuse
  if ($e -notmatch 'hard_refuse_') {
    $e2 = [regex]::Replace($e, '(?s)function Stop-CursorServerProfileTreeIfNeeded \{\s*param\([^)]*\)\s*', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $inject + "`r`n" }, 1)
    if ($e2 -eq $e) { throw 'failed to inject hard_refuse' }
    [IO.File]::WriteAllText($el, $e2, [Text.UTF8Encoding]::new($false))
    Write-Host 'CHANGED editor-launch.ps1 hard_refuse'
  } else { Write-Host 'editor-launch already has hard_refuse' }
} else { throw 'Stop-CursorServerProfileTreeIfNeeded not found' }

Write-Host 'DONE_PATCH'
