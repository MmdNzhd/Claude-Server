# -*- coding: utf-8 -*-
from pathlib import Path
import re

ROOT = Path(r"D:\Smart\Claude-Code-Server")
TARGET = "20260721.43"

el = ROOT / "scripts/client/editor-launch.ps1"
t = el.read_text(encoding="utf-8")

# --- Get-InteractiveWindowsUserQualified ---
old_giu = '''function Get-InteractiveWindowsUser {
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
}'''

new_giu = '''function Get-InteractiveWindowsUser {
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
}

function Get-InteractiveWindowsUserQualified {
    # schtasks /RU needs DOMAIN\\user (short "User" is ambiguous / often fails /IT).
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner -and ($owner -match '\\\\')) { return $owner }
        if ($owner) { return "$env:COMPUTERNAME\\$owner" }
    } catch {}
    $u = Get-InteractiveWindowsUser
    if ($u -match '\\\\') { return $u }
    return "$env:COMPUTERNAME\\$u"
}'''

if old_giu not in t:
    raise SystemExit('Get-InteractiveWindowsUser block not found')
t = t.replace(old_giu, new_giu, 1)
print('OK Get-InteractiveWindowsUserQualified')

# --- Fix CreateProcessWithTokenW: LOGON_WITH_PROFILE + winsta0\\default + no bogus UNICODE env ---
old_cpp = '''        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = 1;
        si.wShowWindow = SW_SHOW;
        PROCESS_INFORMATION pi;
        StringBuilder cmd = new StringBuilder(32768);
        cmd.Append('"');
        cmd.Append(file);
        cmd.Append('"');
        if (!string.IsNullOrEmpty(args)) {
            cmd.Append(' ');
            cmd.Append(args);
        }
        bool ok = CreateProcessWithTokenW(hDup, 0, null, cmd, CREATE_UNICODE_ENVIRONMENT, IntPtr.Zero, null, ref si, out pi);'''

new_cpp = '''        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = "winsta0\\\\default";
        si.dwFlags = 1;
        si.wShowWindow = SW_SHOW;
        PROCESS_INFORMATION pi;
        StringBuilder cmd = new StringBuilder(32768);
        cmd.Append('"');
        cmd.Append(file);
        cmd.Append('"');
        if (!string.IsNullOrEmpty(args)) {
            cmd.Append(' ');
            cmd.Append(args);
        }
        // LOGON_WITH_PROFILE (1): load user hive. Do NOT set CREATE_UNICODE_ENVIRONMENT with
        // null env (that can inherit the elevated block and break GUI apps).
        const uint LOGON_WITH_PROFILE = 0x00000001;
        bool ok = CreateProcessWithTokenW(hDup, LOGON_WITH_PROFILE, null, cmd, 0, IntPtr.Zero, null, ref si, out pi);'''

if old_cpp not in t:
    raise SystemExit('CreateProcessWithTokenW block not found')
t = t.replace(old_cpp, new_cpp, 1)
print('OK CreateProcessWithTokenW')

# --- Initialize-EditorLaunchTask: qualified RU + better helper ---
old_init = '''function Initialize-EditorLaunchTask {
    if ($script:EditorLaunchTaskReady) { return $true }
    $taskName = 'ClaudeServerEditorLaunch'
    $dir = Join-Path $env:LOCALAPPDATA 'ClaudeConnect'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $helper = Join-Path $dir 'launch-editor.ps1'
    @'
$ErrorActionPreference = "Stop"
$specPath = Join-Path $env:LOCALAPPDATA "ClaudeConnect\\launch-spec.json"
$spec = Get-Content $specPath -Raw | ConvertFrom-Json
$args = @()
if ($spec.Args) { $args = @([string[]]$spec.Args) }
Start-Process -FilePath $spec.FilePath -ArgumentList $args -WindowStyle Normal
'@ | Set-Content -Path $helper -Encoding UTF8
    $user = Get-InteractiveWindowsUser
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helper`""
    if ((Invoke-SchTasksQuiet /Query /TN $taskName) -eq 0) {
        [void](Invoke-SchTasksQuiet /Delete /F /TN $taskName)
    }
    $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $user /RL LIMITED /IT
    $script:EditorLaunchTaskReady = ($createExit -eq 0)
    return $script:EditorLaunchTaskReady
}'''

new_init = '''function Initialize-EditorLaunchTask {
    if ($script:EditorLaunchTaskReady) { return $true }
    $taskName = 'ClaudeServerEditorLaunch'
    $dir = Join-Path $env:LOCALAPPDATA 'ClaudeConnect'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $helper = Join-Path $dir 'launch-editor.ps1'
    @'
$ErrorActionPreference = "Stop"
$log = Join-Path $env:LOCALAPPDATA "ClaudeConnect\\launch-editor.log"
function Write-LaunchHelperLog([string]$m) {
  try {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -LiteralPath $log -Value "[$ts] $m" -Encoding UTF8
  } catch {}
}
try {
  $specPath = Join-Path $env:LOCALAPPDATA "ClaudeConnect\\launch-spec.json"
  $spec = Get-Content $specPath -Raw | ConvertFrom-Json
  $args = @()
  if ($spec.Args) { $args = @([string[]]$spec.Args) }
  Write-LaunchHelperLog ("start exe=" + $spec.FilePath + " argc=" + $args.Count)
  $p = Start-Process -FilePath $spec.FilePath -ArgumentList $args -WindowStyle Normal -PassThru
  Write-LaunchHelperLog ("started pid=" + $p.Id)
} catch {
  Write-LaunchHelperLog ("FAIL " + $_.Exception.Message)
  throw
}
'@ | Set-Content -Path $helper -Encoding UTF8
    $user = Get-InteractiveWindowsUserQualified
    Write-EditorLaunchLog "LAUNCH_TASK: recreate RU=$user" 'DEBUG'
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helper`""
    if ((Invoke-SchTasksQuiet /Query /TN $taskName) -eq 0) {
        [void](Invoke-SchTasksQuiet /Delete /F /TN $taskName)
    }
    $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $user /RL LIMITED /IT
    if ($createExit -ne 0) {
        # Fallback: short name (older hosts)
        $short = Get-InteractiveWindowsUser
        Write-EditorLaunchLog "LAUNCH_TASK: qualified RU failed exit=$createExit; retry RU=$short" 'WARN'
        $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $short /RL LIMITED /IT
    }
    $script:EditorLaunchTaskReady = ($createExit -eq 0)
    if (-not $script:EditorLaunchTaskReady) {
        Write-EditorLaunchLog "LAUNCH_TASK: create failed exit=$createExit" 'WARN'
    }
    return $script:EditorLaunchTaskReady
}'''

if old_init not in t:
    raise SystemExit('Initialize-EditorLaunchTask not found')
t = t.replace(old_init, new_init, 1)
print('OK Initialize-EditorLaunchTask')

# --- Force recreate task each connect when RU/helper changes: clear ready flag pattern ---
# Also bump evidence timeout and add elevated Start-Process fallback

old_start = '''function Start-ProcessAsInteractiveUser {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $argPreview = Format-ProcessArgumentString -ArgumentList $ArgumentList
    if (-not (Test-IsElevatedShell)) {
        Write-EditorLaunchLog "PROC_START: mode=non_elevated exe=$FilePath args=$argPreview" 'DEBUG'
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList | Out-Null
        Write-EditorLaunchLog 'PROC_START_OK: mode=non_elevated' 'DEBUG'
        return $true
    }
    Write-EditorLaunchLog "PROC_START: mode=elevated exe=$FilePath args=$argPreview" 'DEBUG'
    Initialize-NonElevatedLauncher
    $argStr = Format-ProcessArgumentString -ArgumentList $ArgumentList
    try {
        if ([NonElevatedLauncher]::Start($FilePath, $argStr)) {
            if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList) {
                Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_non_elevated_launcher' 'DEBUG'
                return $true
            }
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher no_process' 'WARN'
        }
    } catch {
        Write-EditorLaunchLog "PROC_START_WARN: NonElevatedLauncher exception=$($_.Exception.Message)" 'WARN'
    }
    if (-not (Start-ProcessViaLaunchTask -FilePath $FilePath -ArgumentList $ArgumentList)) {
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task schtasks_failed' 'WARN'
        return $false
    }
    if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList) {
        Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_launch_task' 'DEBUG'
        return $true
    }
    Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task no_process' 'WARN'
    return $false
}'''

new_start = '''function Start-ProcessAsInteractiveUser {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $argPreview = Format-ProcessArgumentString -ArgumentList $ArgumentList
    if (-not (Test-IsElevatedShell)) {
        Write-EditorLaunchLog "PROC_START: mode=non_elevated exe=$FilePath args=$argPreview" 'DEBUG'
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList | Out-Null
        Write-EditorLaunchLog 'PROC_START_OK: mode=non_elevated' 'DEBUG'
        return $true
    }
    Write-EditorLaunchLog "PROC_START: mode=elevated exe=$FilePath args=$argPreview" 'DEBUG'
    # Always refresh scheduled task so RU/helper fixes apply every connect run.
    $script:EditorLaunchTaskReady = $false
    Initialize-NonElevatedLauncher
    $argStr = Format-ProcessArgumentString -ArgumentList $ArgumentList
    $evidenceMs = 8000
    try {
        if ([NonElevatedLauncher]::Start($FilePath, $argStr)) {
            if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMs) {
                Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_non_elevated_launcher' 'DEBUG'
                return $true
            }
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher no_process' 'WARN'
        } else {
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher Start=false' 'WARN'
        }
    } catch {
        Write-EditorLaunchLog "PROC_START_WARN: NonElevatedLauncher exception=$($_.Exception.Message)" 'WARN'
    }
    if (Start-ProcessViaLaunchTask -FilePath $FilePath -ArgumentList $ArgumentList) {
        if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMs) {
            Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_launch_task' 'DEBUG'
            return $true
        }
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task no_process' 'WARN'
    } else {
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task schtasks_failed' 'WARN'
    }
    # Last resort: start from the elevated token. Remote-SSH still works; better than
    # false "Cursor not found". Prefer interactive paths above whenever they work.
    try {
        Write-EditorLaunchLog 'PROC_START: mode=elevated_direct_fallback' 'WARN'
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList | Out-Null
        if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMs) {
            Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_direct_fallback' 'WARN'
            return $true
        }
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_direct_fallback no_process' 'ERROR'
    } catch {
        Write-EditorLaunchLog "PROC_START_FAIL: mode=elevated_direct_fallback ex=$($_.Exception.Message)" 'ERROR'
    }
    return $false
}'''

if old_start not in t:
    raise SystemExit('Start-ProcessAsInteractiveUser not found')
t = t.replace(old_start, new_start, 1)
print('OK Start-ProcessAsInteractiveUser')

el.write_text(t, encoding="utf-8", newline="\n")
print("WROTE editor-launch.ps1")

# --- connect.ps1: clearer StepFail messages ---
cp = ROOT / "scripts/client/windows/connect.ps1"
ct = cp.read_text(encoding="utf-8")
old_msg = 'StepFail "$EditorName not found (install Cursor or VS Code + Remote-SSH)"'
new_msg = 'StepFail "$EditorName failed to start (elevated launch). Keep connect open and press O, or launch Cursor manually with ClaudeServerCursorProfile."'
count = ct.count(old_msg)
if count < 1:
    raise SystemExit('StepFail message not found in connect.ps1')
ct = ct.replace(old_msg, new_msg)
cp.write_text(ct, encoding="utf-8", newline="\n")
print(f"OK connect.ps1 messages replaced count={count}")

# versions
for rel in ["scripts/client/windows/connect-version.txt", "scripts/client/mac/connect-version.txt"]:
    (ROOT / rel).write_text(TARGET + "\n", encoding="utf-8", newline="\n")
for path, pat, repl in [
    (ROOT / "scripts/client/windows/connect.ps1", r"ConnectVersion = '20260721\.\d+'", f"ConnectVersion = '{TARGET}'"),
    (ROOT / "scripts/client/mac/connect.sh", r"CONNECT_VERSION='20260721\.\d+'", f"CONNECT_VERSION='{TARGET}'"),
]:
    tt = path.read_text(encoding="utf-8")
    tt2, n = re.subn(pat, repl, tt, count=1)
    if n != 1:
        raise SystemExit(f"version bump fail {path}")
    path.write_text(tt2, encoding="utf-8", newline="\n")
    print(f"bumped {path.name}")

print("DONE", TARGET)
