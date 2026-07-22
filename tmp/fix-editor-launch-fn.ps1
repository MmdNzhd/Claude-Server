$ErrorActionPreference = 'Stop'
$path = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$raw = [IO.File]::ReadAllText($path)
$broken = @'
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
][string]$Reason,
        [switch]$Force
    )
    # WARNING: -Force kills EVERY Cursor process using ClaudeServerCursorProfile
    # (all open remote projects). Launch-RemoteEditor must NOT call this with -Force.
    # Kept for rare operator/manual recovery only.
    $procs = @(Get-CursorProfileProcesses)
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=0" 'DEBUG'
        return 0
    }
    if (-not $Force) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=$($procs.Count) force_not_set" 'DEBUG'
        return 0
    }
    Write-EditorLaunchLog "LAUNCH_KILL: reason=$Reason profile_count=$($procs.Count) elevated=$(Test-IsElevatedShell) WARNING=closes_all_profile_windows" 'WARN'
    Stop-CursorServerProfileTree
    Start-Sleep -Milliseconds 400
    $remaining = @(Get-CursorProfileProcesses).Count
    Write-EditorLaunchLog "LAUNCH_KILL_DONE: remaining_profile_procs=$remaining" 'INFO'
    return $procs.Count
}
'@
$fixed = @'
function Stop-CursorServerProfileTreeIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [switch]$Force
    )
    # Hard refuse: auth / proxy / tunnel recovery must never wipe shared profile windows
    # (VPN flap -> TUNNEL_DROP -> force_auth historically soft-stopped profile_count=14..24).
    if ($Reason -match 'auth|proxy|recovery') {
        $n = @(Get-CursorProfileProcesses).Count
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=hard_refuse_$Reason profile_count=$n force=$Force") 'WARN'
        return 0
    }
    # WARNING: -Force kills EVERY Cursor process using ClaudeServerCursorProfile
    # (all open remote projects). Launch-RemoteEditor must NOT call this with -Force.
    # Kept for rare operator/manual recovery only.
    $procs = @(Get-CursorProfileProcesses)
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=0" 'DEBUG'
        return 0
    }
    if (-not $Force) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=$($procs.Count) force_not_set" 'DEBUG'
        return 0
    }
    Write-EditorLaunchLog "LAUNCH_KILL: reason=$Reason profile_count=$($procs.Count) elevated=$(Test-IsElevatedShell) WARNING=closes_all_profile_windows" 'WARN'
    Stop-CursorServerProfileTree
    Start-Sleep -Milliseconds 400
    $remaining = @(Get-CursorProfileProcesses).Count
    Write-EditorLaunchLog "LAUNCH_KILL_DONE: remaining_profile_procs=$remaining" 'INFO'
    return $procs.Count
}
'@
# Normalize CRLF for match
$rawN = $raw -replace "`r`n", "`n"
$brokenN = $broken -replace "`r`n", "`n"
$fixedN = $fixed -replace "`r`n", "`n"
if (-not $rawN.Contains($brokenN)) {
  # try to find orphan marker
  if ($rawN -match '\]\[string\]\$Reason') {
    throw 'broken marker present but exact block mismatch'
  }
  if ($rawN -match 'hard_refuse_' -and $rawN -notmatch '\]\[string\]\$Reason') {
    Write-Host 'ALREADY_FIXED'
    exit 0
  }
  throw 'unexpected state'
}
$outN = $rawN.Replace($brokenN, $fixedN)
$out = $outN -replace "`n", "`r`n"
[IO.File]::WriteAllText($path, $out, [Text.UTF8Encoding]::new($false))
$errs = $null
$tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'PARSE_FAIL' }
Write-Host 'FIXED_AND_PARSE_OK'
# re-sync
Copy-Item -Force $path 'C:\Users\Smart\Desktop\Claude-Connect\editor-launch.ps1'
Copy-Item -Force $path 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\editor-launch.ps1'
Copy-Item -Force 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' 'C:\Users\Smart\Desktop\Claude-Connect\connect.ps1'
Copy-Item -Force 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.ps1'
Write-Host 'RESYNC_OK'
