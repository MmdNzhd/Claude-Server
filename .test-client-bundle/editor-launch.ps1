# editor-launch.ps1 - shared VS Code/Cursor launch (dot-sourced by connect.ps1)
# Same pattern as mac/connect.sh:  cursor|code --folder-uri "vscode-remote://..."

function Get-CursorRemoteProfileDir {
    # Isolated Cursor profile for server Remote-SSH sessions. Launching with
    # --user-data-dir here keeps the server's shared golden identity in its
    # own storage, completely separate from the developer's personal Cursor
    # profile (default %APPDATA%\Cursor) - so the personal login is never
    # read, overwritten, or force-closed to make room for the server one.
    return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile')
}

function Initialize-CursorServerProfile {
    # First-run only: make the server window visually distinct from personal Cursor.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (Test-Path $settingsPath) { return }
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    @'
{
  "window.title": "${dirty}${activeEditorShort}${separator}[Claude Server] ${rootName}",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#1e3a5f",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "#152a45",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
'@ | Set-Content -Path $settingsPath -Encoding UTF8
}


function Set-CursorProxySettings {
    # Points Cursor's own network stack (not just extensions) at the local -L forward that
    # git-mode.ps1 opened on the reverse-tunnel ssh process (server xray), so Cursor's
    # chat/agent/MCP requests egress via the VLESS exit IP instead of each laptop's own network.
    # settings.json http.proxy must be http:// (Node/undici rejects socks5); Chromium CLI stays socks5.
    param(
        [int]$SocksPort = 0,
        [int]$HttpPort = 0
    )
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }
    if ($HttpPort -gt 0) {
        $proxyUrl = "http://127.0.0.1:$HttpPort"
    } elseif ($SocksPort -gt 0) {
        # Never write socks5 into settings.json: Cursor Node/MCP undici rejects it
        # ("Invalid URL protocol"). Chromium still uses --proxy-server=socks5 via CLI args.
        Write-EditorLaunchLog ("CURSOR_PROXY_SET: skip_settings no_http_leg socks={0} (CLI socks only)" -f $SocksPort) 'WARN'
        return $false
    } else {
        return $false
    }
    $obj = $null
    if (Test-Path $settingsPath) {
        try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
    }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    $changed = $false
    foreach ($pair in @(
        @{ Name = 'http.proxy'; Value = $proxyUrl }
        @{ Name = 'http.proxyStrictSSL'; Value = $false }
        @{ Name = 'http.proxySupport'; Value = 'override' }
        @{ Name = 'cursor.general.proxyMode'; Value = 'custom' }
        @{ Name = 'cursor.general.disableHttp2'; Value = $true }
    )) {
        $prop = $obj.PSObject.Properties[$pair.Name]
        if ($prop) {
            if ("$($prop.Value)" -ne "$($pair.Value)") { $prop.Value = $pair.Value; $changed = $true }
        } else {
            $obj | Add-Member -NotePropertyName $pair.Name -NotePropertyValue $pair.Value -Force
            $changed = $true
        }
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog "CURSOR_PROXY_SET: proxy=$proxyUrl changed=1" 'INFO'
    }
    return $changed
}

function Clear-CursorProxySettings {
    # Remove proxy keys when xray is down or server has no xray (Sepidz) - must match no-feature state.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $settingsPath)) { return $false }
    $obj = $null
    try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    if (-not $obj) { return $false }
    $changed = $false
    foreach ($key in @('http.proxy', 'http.proxyStrictSSL', 'http.proxySupport', 'cursor.general.proxyMode', 'cursor.general.disableHttp2')) {
        $prop = $obj.PSObject.Properties[$key]
        if ($prop) {
            $obj.PSObject.Properties.Remove($key)
            $changed = $true
        }
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: removed proxy keys changed=1' 'INFO'
    }
    return $changed
}

function Get-CodeRemoteProfileDir {
    # Isolated VS Code profile for server Remote-SSH (parity with Mac ClaudeServerCodeProfile).
    return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCodeProfile')
}

function Initialize-CodeServerProfile {
    $userDir = Join-Path (Get-CodeRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (Test-Path $settingsPath) { return }
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    @'
{
  "window.title": "${dirty}${activeEditorShort}${separator}[Claude Server Code] ${rootName}",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#1e3a5f",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "#152a45",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
'@ | Set-Content -Path $settingsPath -Encoding UTF8
}

function Ensure-EditorOnPath {
    param([string]$EditorCmd)
    $leaf = if ($EditorCmd -eq 'cursor') { 'cursor.cmd' } else { 'code.cmd' }
    $exeLeaf = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $relBin = if ($EditorCmd -eq 'cursor') { 'resources\app\bin' } else { 'bin' }
    $folder = if ($EditorCmd -eq 'cursor') { 'cursor' } else { 'Microsoft VS Code' }

    function ConvertTo-EditorCliFromRoot {
        param([string]$Root)
        if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
        $binDir = [System.IO.Path]::Combine($Root, $relBin)
        $cli = [System.IO.Path]::Combine($binDir, $leaf)
        if (Test-Path -LiteralPath $cli) { return $cli }
        $exe = [System.IO.Path]::Combine($Root, $exeLeaf)
        if (Test-Path -LiteralPath $exe) { return $exe }
        return $null
    }

    function Add-EditorBinToPath {
        param([string]$CliPath)
        if (-not $CliPath) { return $null }
        $binDir = Split-Path -Parent $CliPath
        # If we resolved Cursor.exe at install root, prefer resources\app\bin when present
        if ($CliPath -match '\\Cursor\.exe$' -or $CliPath -match '\\Code\.exe$') {
            $maybeBin = [System.IO.Path]::Combine((Split-Path -Parent $CliPath), $relBin)
            $maybeCli = [System.IO.Path]::Combine($maybeBin, $leaf)
            if (Test-Path -LiteralPath $maybeCli) {
                $CliPath = $maybeCli
                $binDir = $maybeBin
            }
        }
        if ($binDir -and ($env:Path -notlike "*$([regex]::Escape($binDir))*")) {
            $env:Path = "$binDir;$env:Path"
        }
        return $CliPath
    }

    # 1) Preferred accounts first (LaptopUser / current), then every local profile.
    #    Fixes Admin connect when Cursor is installed under another Windows user.
    $userNames = New-Object System.Collections.Generic.List[string]
    foreach ($u in @($script:LaptopUser, $env:USERNAME)) {
        if ($u -and -not $userNames.Contains($u)) { [void]$userNames.Add($u) }
    }
    $usersRoot = 'C:\Users'
    if (Test-Path -LiteralPath $usersRoot) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') } |
            ForEach-Object {
                if (-not $userNames.Contains($_.Name)) { [void]$userNames.Add($_.Name) }
            }
    }

    foreach ($u in $userNames) {
        $root = [System.IO.Path]::Combine("C:\Users\$u\AppData\Local\Programs", $folder)
        $hit = ConvertTo-EditorCliFromRoot -Root $root
        if ($hit) { return (Add-EditorBinToPath -CliPath $hit) }
    }

    # 2) Current LOCALAPPDATA + machine-wide Program Files
    $candidateRoots = @(
        $(if ($env:LOCALAPPDATA) { [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', $folder) } else { $null }),
        $(if ($env:ProgramFiles) { [System.IO.Path]::Combine($env:ProgramFiles, $folder) } else { $null }),
        $(if (${env:ProgramFiles(x86)}) { [System.IO.Path]::Combine(${env:ProgramFiles(x86)}, $folder) } else { $null })
    ) | Where-Object { $_ }
    foreach ($root in $candidateRoots) {
        $hit = ConvertTo-EditorCliFromRoot -Root $root
        if ($hit) { return (Add-EditorBinToPath -CliPath $hit) }
    }

    # 3) Already on PATH (Get-Command)
    $cmd = Get-Command $EditorCmd -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return (Add-EditorBinToPath -CliPath $cmd.Source)
    }

    return $null
}

function Show-EditorAutoPick {
    param(
        [Parameter(Mandatory)][string]$PickedName,
        [Parameter(Mandatory)][string]$OtherName,
        [Parameter(Mandatory)][string]$OtherReason
    )
    Write-Host ''
    Write-Host '    Open with' -ForegroundColor White
    Write-Host ''
    Write-Host "    $PickedName  <- only option, opening automatically" -ForegroundColor DarkGray
    Write-Host "    $OtherName  (unavailable - $OtherReason)" -ForegroundColor DarkGray
    Write-Host ''
}

function Get-EditorPref {
    param([Parameter(Mandatory)][string]$CfgDir)
    $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
    if (-not (Test-Path $EditorPrefFile)) { return 'cursor' }
    $saved = (Get-Content $EditorPrefFile -Raw -ErrorAction SilentlyContinue).Trim().ToLower()
    if ($saved -eq 'vscode') { $saved = 'code' }
    if ($saved -match '^(rider|both)$') { Remove-Item $EditorPrefFile -ErrorAction SilentlyContinue; return 'cursor' }
    if ($saved -in @('cursor', 'code', 'ask')) { return $saved }
    return 'cursor'
}

function Show-EditorPickMenu {
    param(
        [Parameter(Mandatory)][string]$CfgDir,
        [string]$Saved = 'cursor',
        [switch]$PersistChoice
    )
    Write-Host ''
    Write-Host '    Open with' -ForegroundColor White
    Write-Host ''
    Write-Host '    1  Cursor' -ForegroundColor DarkGray
    Write-Host '    2  VS Code' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "    (Enter = $Saved)" -ForegroundColor DarkGray
    $edChoice = (Read-Host '    >').Trim().ToLower()
    $EditorCmd = 'cursor'
    $EditorName = 'Cursor'
    switch ($edChoice) {
        { $_ -in '1', 'cursor', 'c' } { $EditorCmd = 'cursor'; $EditorName = 'Cursor' }
        { $_ -in '2', 'code', 'vscode', 'v' } { $EditorCmd = 'code'; $EditorName = 'VS Code' }
        '' {
            if ($Saved -eq 'code') { $EditorCmd = 'code'; $EditorName = 'VS Code' }
        }
        default { $EditorCmd = 'cursor'; $EditorName = 'Cursor' }
    }
    if ($PersistChoice) {
        $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
        Set-Content -Path $EditorPrefFile -Value $EditorCmd -Encoding ASCII | Out-Null
    }
    return ,([PSCustomObject]@{ EditorCmd = $EditorCmd; EditorName = $EditorName })
}

function Configure-EditorPref {
    param([Parameter(Mandatory)][string]$CfgDir)
    Write-Host ''
    Write-Host '    IDE preference' -ForegroundColor White
    Write-Host ''
    $cur = Get-EditorPref -CfgDir $CfgDir
    Write-Host "    Current: $cur" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    1  cursor - always open Cursor' -ForegroundColor DarkGray
    Write-Host '    2  code   - always open VS Code' -ForegroundColor DarkGray
    Write-Host '    3  ask    - pick each connect' -ForegroundColor DarkGray
    Write-Host ''
    $choice = (Read-Host '    >').Trim().ToLower()
    $val = switch ($choice) {
        { $_ -in '1', 'cursor', 'c' } { 'cursor' }
        { $_ -in '2', 'code', 'vscode', 'v' } { 'code' }
        { $_ -in '3', 'ask', 'a' } { 'ask' }
        default { $null }
    }
    if (-not $val) { Warn 'Invalid choice.'; return }
    Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'editor.conf')) -Value $val -Encoding ASCII | Out-Null
    Write-Host "    Saved: $val" -ForegroundColor Green
    Write-Host ''
}

function Resolve-EditorChoice {
    param(
        [Parameter(Mandatory)][string]$CfgDir
    )

    # Path.Combine - Join-Path binds pipeline input and causes ChildPath prompt
    $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
    Ensure-EditorOnPath 'cursor' | Out-Null
    Ensure-EditorOnPath 'code' | Out-Null
    $haveCursor = [bool](Get-Command cursor -ErrorAction SilentlyContinue)
    $haveCode   = [bool](Get-Command code   -ErrorAction SilentlyContinue)

    if (-not $haveCursor -and -not $haveCode) {
        return $null
    }

    if ($haveCursor -and -not $haveCode) {
        Show-EditorAutoPick -PickedName 'Cursor' -OtherName 'VS Code' -OtherReason 'not installed, or missing the Remote-SSH extension'
        return ,([PSCustomObject]@{ EditorCmd = 'cursor'; EditorName = 'Cursor' })
    }
    if (-not $haveCursor -and $haveCode) {
        Show-EditorAutoPick -PickedName 'VS Code' -OtherName 'Cursor' -OtherReason 'not installed, or install is broken'
        return ,([PSCustomObject]@{ EditorCmd = 'code'; EditorName = 'VS Code' })
    }

    $pref = Get-EditorPref -CfgDir $CfgDir
    if ($pref -eq 'ask') {
        return ,@(Show-EditorPickMenu -CfgDir $CfgDir -Saved 'cursor' -PersistChoice)[-1]
    }
    if ($pref -eq 'code') {
        return ,([PSCustomObject]@{ EditorCmd = 'code'; EditorName = 'VS Code' })
    }
    return ,([PSCustomObject]@{ EditorCmd = 'cursor'; EditorName = 'Cursor' })
}

function Test-IsElevatedShell {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveWindowsUser {
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
}

function Get-InteractiveWindowsUserQualified {
    # schtasks /RU needs DOMAIN\user (short "User" is ambiguous / often fails /IT).
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner -and ($owner -match '\\')) { return $owner }
        if ($owner) { return "$env:COMPUTERNAME\$owner" }
    } catch {}
    $u = Get-InteractiveWindowsUser
    if ($u -match '\\') { return $u }
    return "$env:COMPUTERNAME\$u"
}

function Get-EditorNativeExe {
    param([Parameter(Mandatory)][string]$EditorCmd)
    $cli = Ensure-EditorOnPath $EditorCmd
    if (-not $cli) { return $null }
    if ($EditorCmd -ne 'cursor') { return $cli }
    if ($cli -match '\\Cursor\.exe$') { return $cli }
    $binDir = Split-Path $cli -Parent
    $root = Split-Path (Split-Path (Split-Path $binDir -Parent) -Parent) -Parent
    $exe = Join-Path $root 'Cursor.exe'
    if (Test-Path $exe) { return $exe }
    return $cli
}

function Show-ConnectConsoleIfHidden {
    try {
        if (-not ('Win32.ConnectConsole' -as [type])) {
            Add-Type -Name ConnectConsole -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        }
        [Win32.ConnectConsole]::ShowWindow([Win32.ConnectConsole]::GetConsoleWindow(), 5) | Out-Null
    } catch {}
}

function Stop-CursorServerProfileTree {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    $procs = @(Get-CursorProfileProcesses -ProfileDir $ProfileDir)
    if ($procs.Count -eq 0) { return }
    $seen = @{}
    foreach ($p in $procs) {
        if ($seen[$p.ProcessId]) { continue }
        $seen[$p.ProcessId] = $true
        $cmd = Format-EditorProcessCommandLine -CommandLine $p.CommandLine -MaxLen 120
        Write-EditorLaunchLog "LAUNCH_KILL_PROC: pid=$($p.ProcessId) cmd=$cmd" 'DEBUG'
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 200
}

function Initialize-NonElevatedLauncher {
    if ($script:NonElevatedLauncherReady) { return }
    if (-not ('NonElevatedLauncher' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class NonElevatedLauncher
{
    const int PROCESS_QUERY_INFORMATION = 0x0400;
    const uint TOKEN_DUPLICATE = 0x0002;
    const uint TOKEN_QUERY = 0x0008;
    const uint TOKEN_ASSIGN_PRIMARY = 0x0001;
    const int SecurityImpersonation = 2;
    const int TokenPrimary = 1;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    const int SW_SHOW = 5;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
        public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr tok);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool DuplicateTokenEx(IntPtr hExisting, uint dwDesiredAccess, IntPtr lpTokenAttributes, int ImpersonationLevel, int TokenType, out IntPtr phNewToken);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessWithTokenW(IntPtr hToken, uint dwLogonFlags, string lpApplicationName, StringBuilder lpCommandLine, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    static Process FindExplorer() {
        int sid = Process.GetCurrentProcess().SessionId;
        foreach (Process p in Process.GetProcessesByName("explorer")) {
            if (p.SessionId == sid) { return p; }
        }
        return null;
    }

    public static bool Start(string file, string args) {
        Process explorer = FindExplorer();
        if (explorer == null) { return false; }
        IntPtr hProc = OpenProcess(PROCESS_QUERY_INFORMATION, false, explorer.Id);
        if (hProc == IntPtr.Zero) { return false; }
        IntPtr hTok;
        if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY, out hTok)) {
            CloseHandle(hProc);
            return false;
        }
        IntPtr hDup;
        if (!DuplicateTokenEx(hTok, TOKEN_ASSIGN_PRIMARY | TOKEN_DUPLICATE | TOKEN_QUERY, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out hDup)) {
            CloseHandle(hTok);
            CloseHandle(hProc);
            return false;
        }
        CloseHandle(hTok);
        CloseHandle(hProc);
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = "winsta0\\default";
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
        bool ok = CreateProcessWithTokenW(hDup, LOGON_WITH_PROFILE, null, cmd, 0, IntPtr.Zero, null, ref si, out pi);
        CloseHandle(hDup);
        if (ok) {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
        return ok;
    }
}
'@ -ErrorAction Stop
    }
    $script:NonElevatedLauncherReady = $true
}

function Invoke-SchTasksQuiet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'schtasks.exe'
    $psi.Arguments = (($ArgumentList | ForEach-Object {
        if ($null -eq $_) { return '' }
        $s = [string]$_
        if ($s -match '\s') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    [void]$p.StandardOutput.ReadToEnd()
    [void]$p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return $p.ExitCode
}

function Initialize-EditorLaunchTask {
    if ($script:EditorLaunchTaskReady) { return $true }
    $taskName = 'ClaudeServerEditorLaunch'
    $dir = Join-Path $env:LOCALAPPDATA 'ClaudeConnect'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $helper = Join-Path $dir 'launch-editor.ps1'
    @'
$ErrorActionPreference = "Stop"
$log = Join-Path $env:LOCALAPPDATA "ClaudeConnect\launch-editor.log"
function Write-LaunchHelperLog([string]$m) {
  try {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -LiteralPath $log -Value "[$ts] $m" -Encoding UTF8
  } catch {}
}
try {
  $specPath = Join-Path $env:LOCALAPPDATA "ClaudeConnect\launch-spec.json"
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
}

function Start-ProcessViaLaunchTask {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    if (-not (Initialize-EditorLaunchTask)) { return $false }
    $specPath = Join-Path $env:LOCALAPPDATA 'ClaudeConnect\launch-spec.json'
    @{ FilePath = $FilePath; Args = $ArgumentList } | ConvertTo-Json -Compress | Set-Content -Path $specPath -Encoding UTF8
    return ((Invoke-SchTasksQuiet /Run /TN 'ClaudeServerEditorLaunch') -eq 0)
}

function Format-ProcessArgumentString {
    param([string[]]$ArgumentList)
    return (($ArgumentList | ForEach-Object {
        if ($null -eq $_) { return '' }
        $s = [string]$_
        if ($s -match '\s') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' ')
}


function Get-EditorExeNameFromPath {
    param([Parameter(Mandatory)][string]$FilePath)
    $leaf = Split-Path $FilePath -Leaf
    if ($leaf -match '(?i)^cursor(\.exe|\.cmd)?$') { return 'Cursor.exe' }
    if ($leaf -match '(?i)^code(\.exe|\.cmd)?$') { return 'Code.exe' }
    if ($leaf -match '\.exe$') { return $leaf }
    return $null
}

function Get-EditorProfileDirFromArgs {
    param([string[]]$ArgumentList = @())
    for ($i = 0; $i -lt ($ArgumentList.Count - 1); $i++) {
        if ($ArgumentList[$i] -eq '--user-data-dir') { return $ArgumentList[$i + 1] }
    }
    return $null
}

function Test-EditorProcessEvidence {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutMs = 2000
    )
    $exeName = Get-EditorExeNameFromPath -FilePath $FilePath
    if (-not $exeName) { return $false }
    $profileDir = Get-EditorProfileDirFromArgs -ArgumentList $ArgumentList
    $profileNeedle = if ($profileDir) { [regex]::Escape($profileDir) } else { $null }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
        $procs = @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'proc_start_verify' -ForceRefresh)
        if ($profileNeedle) {
            $procs = @($procs | Where-Object { $_.CommandLine -and ($_.CommandLine -match $profileNeedle) })
        }
        if ($procs.Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Get-EditorProfileProcessesForLaunch {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [switch]$ForceRefresh
    )
    $exeName = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $profileDir = if ($EditorCmd -eq 'cursor') { Get-CursorRemoteProfileDir } else { Get-CodeRemoteProfileDir }
    if (-not $profileDir) { return @() }
    $needle = [regex]::Escape($profileDir)
    return @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'launch_profile_verify' -ForceRefresh:$ForceRefresh |
        Where-Object { $_.CommandLine -and ($_.CommandLine -match $needle) })
}

function Confirm-RemoteEditorLaunchVisible {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [int]$WaitMs = 500
    )
    # Check immediately first - the caller only reaches this function after Launch-RemoteEditor
    # already positively confirmed on_folder via its own poll loop moments earlier, so the
    # common case is already-true and the flat WaitMs sleep below was pure dead time on top of
    # that. Only sleep-and-retry (preserving the original WaitMs budget as a safety net for the
    # genuine elevated-launch window-visibility race) when the immediate check comes up empty.
    if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
    if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    if (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    if ($WaitMs -gt 0) {
        Start-Sleep -Milliseconds $WaitMs
        if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
        if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
        if (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    }
    $profileProcs = @(Get-EditorProfileProcessesForLaunch -EditorCmd $EditorCmd -ForceRefresh)
    if ($profileProcs.Count -eq 0) { return $false }
    $mainProcs = if ($EditorCmd -eq 'cursor') {
        @(Get-CursorMainProfileProcesses)
    } else {
        @($profileProcs | Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') })
    }
    if ($mainProcs.Count -eq 0) { return $false }
    foreach ($p in $mainProcs) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { return $true }
        } catch {}
    }
    return $false
}

function Start-ProcessAsInteractiveUser {
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
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher no_process' 'DEBUG'
        } else {
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher Start=false' 'DEBUG'
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
}

$script:EditorCimCache = @{}
$script:EditorCimCacheTtlSec = 2
$script:LaunchCimCallCount = 0
$script:VerboseLaunch = ($env:CLAUDE_CONNECT_VERBOSE_LAUNCH -eq '1')

function Clear-CursorProcessCache {
    $script:EditorCimCache = @{}
}

function Test-LaunchPerfEnabled {
    if (Get-Command Test-ConnectPerfEnabled -ErrorAction SilentlyContinue) {
        return [bool](Test-ConnectPerfEnabled)
    }
    # Keep the standalone fallback aligned with connect-ui.ps1: PERF is opt-in.
    return ($env:CLAUDE_CONNECT_PERF_LOG -eq '1')
}

function Write-LaunchPerfLog {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Extra = ''
    )
    if (-not (Test-LaunchPerfEnabled)) { return }
    $cim = if ($null -ne $script:LaunchCimCallCount) { $script:LaunchCimCallCount } else { 0 }
    $fullExtra = "cim_total=$cim" + $(if ($Extra) { " $Extra" } else { '' })
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark $Mark -Ms $Ms -Extra $fullExtra
    } else {
        Write-EditorLaunchLog "PERF[$Mark] ms=$Ms $fullExtra" 'DEBUG'
    }
}

function Invoke-CimEditorProcessQuery {
    param(
        [Parameter(Mandatory)][string]$ExeName,
        [string]$Reason = 'unspecified',
        [switch]$ForceRefresh
    )
    if ($null -eq $script:LaunchCimCallCount) { $script:LaunchCimCallCount = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Bug 48: TTL so closed editors are detected (cache must expire).
    if (-not $script:EditorCimCacheTtlSec) { $script:EditorCimCacheTtlSec = 2 }
    if (-not $ForceRefresh -and $script:EditorCimCache.ContainsKey($ExeName)) {
        $entry = $script:EditorCimCache[$ExeName]
        $cached = $null
        $ageOk = $false
        if ($entry -is [hashtable] -and $entry.ContainsKey('At') -and $entry.ContainsKey('Procs')) {
            $ageOk = ((Get-Date) - [datetime]$entry.At).TotalSeconds -lt [double]$script:EditorCimCacheTtlSec
            $cached = @($entry.Procs)
        } else {
            # Legacy bare array entry - treat as expired.
            $cached = @($entry)
            $ageOk = $false
        }
        if ($ageOk) {
            $sw.Stop()
            Write-LaunchPerfLog -Mark 'cim_query' -Ms $sw.ElapsedMilliseconds -Extra "reason=$Reason count=$($cached.Count) cache_hit=1 exe=$ExeName"
            return $cached
        }
    }
    $result = @(Get-CimInstance Win32_Process -Filter "Name='$ExeName'" -Property ProcessId,Name,CommandLine -ErrorAction SilentlyContinue)
    $script:EditorCimCache[$ExeName] = @{ At = Get-Date; Procs = $result }
    $script:LaunchCimCallCount++
    $sw.Stop()
    Write-LaunchPerfLog -Mark 'cim_query' -Ms $sw.ElapsedMilliseconds -Extra "reason=$Reason count=$($result.Count) cache_hit=0 exe=$ExeName"
    return $result
}

function Invoke-CimCursorProcessQuery {
    param(
        [string]$Reason = 'unspecified',
        [switch]$ForceRefresh
    )
    return @(Invoke-CimEditorProcessQuery -ExeName 'Cursor.exe' -Reason $Reason -ForceRefresh:$ForceRefresh)
}

function Get-CursorProfileProcesses {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [switch]$ForceRefresh
    )
    if (-not $ProfileDir) { return @() }
    $needle = [regex]::Escape($ProfileDir)
    return @(Invoke-CimCursorProcessQuery -Reason 'profile_procs' -ForceRefresh:$ForceRefresh |
        Where-Object { $_.CommandLine -and ($_.CommandLine -match $needle) })
}

function Test-PathNeedleBoundaryMatch {
    # Boundary-safe substring check: NeedleEscaped must match exactly, or be immediately
    # followed by a path separator / quote character, or end-of-string. A bare substring
    # test wrongly matches a shorter project path inside a longer one that shares the same
    # prefix (e.g. ".../ai-gap" incorrectly matching inside ".../ai-gap-summay").
    param(
        [string]$CommandLine,
        [Parameter(Mandatory)][string]$NeedleEscaped
    )
    if (-not $CommandLine) { return $false }
    return [bool]($CommandLine -match "$NeedleEscaped(?:[\\/`"']|$)")
}

function Get-RemoteEditorProcesses {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$ForceRefresh
    )
    $exe = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $uriNeedle = "ssh-remote+${Alias}"
    $pathNeedle = $RemotePath.TrimEnd('/')
    $pathNeedleEsc = [regex]::Escape($pathNeedle)
    $profileDir = if ($EditorCmd -eq 'cursor') { Get-CursorRemoteProfileDir } elseif ($EditorCmd -eq 'code') { Get-CodeRemoteProfileDir } else { $null }

    $matches = @(Invoke-CimEditorProcessQuery -ExeName $exe -Reason 'remote_editor_procs' -ForceRefresh:$ForceRefresh |
        Where-Object {
            $cmd = $_.CommandLine
            if (-not $cmd) { return $false }
            if (-not (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedleEsc)) { return $false }
            if ($cmd -match [regex]::Escape($uriNeedle)) { return $true }
            if ($profileDir -and ($cmd -match [regex]::Escape($profileDir))) { return $true }
            return $false
        })
    return $matches
}

function Test-RemoteEditorWindowOpen {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Auth gate: on correct folder AND a visible process with uri/path match.
    if (-not (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        return $false
    }
    return (Test-RemoteEditorWindowOpenWhenOnFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
}

function Test-RemoteEditorWindowOpenWhenOnFolder {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    foreach ($p in @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { return $true }
        } catch {}
    }
    if ($EditorCmd -eq 'cursor') {
        foreach ($p in @(Get-CursorMainProfileProcesses)) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { return $true }
            } catch {}
        }
    }
    return $false
}

function Get-RemoteFolderUri {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $path = $RemotePath.TrimEnd('/')
    return "vscode-remote://ssh-remote+${Alias}${path}"
}

function Get-CursorMainProfileProcesses {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    return @(Get-CursorProfileProcesses -ProfileDir $ProfileDir |
        Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') })
}

function Get-CursorMainPersonalProcesses {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [switch]$ForceRefresh
    )
    if (-not $ProfileDir) { return @() }
    $profileEsc = [regex]::Escape($ProfileDir)
    return @(Invoke-CimCursorProcessQuery -Reason 'personal_procs' -ForceRefresh:$ForceRefresh |
        Where-Object {
            $_.CommandLine -and ($_.CommandLine -notmatch $profileEsc) -and ($_.CommandLine -notmatch '--type=')
        })
}

function Test-PersonalCursorDominant {
    $personalMain = @(Get-CursorMainPersonalProcesses).Count
    $profileMain = @(Get-CursorMainProfileProcesses).Count
    return ($personalMain -ge 3 -and $profileMain -eq 0)
}

function Test-CursorWindowTitleIsAgentHome {
    param(
        [string]$Title,
        [string]$ProjectRootName = ''
    )
    if (-not $Title) { return $false }
    if ($ProjectRootName -and $Title -match '\[Claude Server\]' -and $Title -match [regex]::Escape($ProjectRootName)) {
        return $false
    }
    if ($Title -match '(?i)^cursor agents$|cursor agents\b|agent home') { return $true }
    return $false
}

function Test-CursorWindowShowsAgentHome {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$RemotePath = ''
    )
    $rootName = ''
    if ($RemotePath) { $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1] }
    try {
        $wp = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        return (Test-CursorWindowTitleIsAgentHome -Title $wp.MainWindowTitle -ProjectRootName $rootName)
    } catch { }
    return $false
}

function Test-RemoteEditorOnCorrectFolder {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    if ($EditorCmd -ne 'cursor') {
        return (Test-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath).Count -gt 0
    }
    if (Test-RemoteEditorInAgentHome -RemotePath $RemotePath) { return $false }
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $pathNeedle = [regex]::Escape($RemotePath.TrimEnd('/'))
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        $cmd = $p.CommandLine
        if ($cmd) {
            if ($cmd -match $uriNeedle) {
                if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                    return $true
                }
                continue
            }
            if ($cmd -match $aliasNeedle -and (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedle)) {
                if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                    return $true
                }
                continue
            }
        }
        if ($rootNeedle) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                $title = $wp.MainWindowTitle
                # Accept either our custom "[Claude Server] <root>" title template or Cursor's own
                # default Remote-SSH title "... [SSH: <alias>] - Cursor" - the custom template doesn't
                # apply while a built-in view (e.g. Settings) is focused, so both must be recognized.
                if ($title -and $title -match $rootNeedle -and
                    ($title -match '\[Claude Server\]' -or $title -match "(?i)\[SSH:\s*${aliasOnlyNeedle}\]")) {
                    return $true
                }
            } catch { }
        }
    }
    return $false
}

function Get-RemoteEditorSessionPresence {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Bug 60: single-pass on_folder + window_open (one CIM walk via shared cache).
    $onFolder = $false
    $windowOpen = $false
    if ($EditorCmd -ne 'cursor') {
        $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
        $onFolder = ($matched.Count -gt 0)
        foreach ($p in $matched) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true; break }
            } catch { }
        }
        return [pscustomobject]@{ OnFolder = [bool]$onFolder; WindowOpen = [bool]$windowOpen }
    }
    if (Test-RemoteEditorInAgentHome -RemotePath $RemotePath) {
        $mains = @(Get-CursorMainProfileProcesses)
        foreach ($p in $mains) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true; break }
            } catch { }
        }
        return [pscustomobject]@{ OnFolder = $false; WindowOpen = [bool]$windowOpen }
    }
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $pathNeedle = [regex]::Escape($RemotePath.TrimEnd('/'))
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        $cmd = $p.CommandLine
        $hit = $false
        if ($cmd) {
            if ($cmd -match $uriNeedle) { $hit = $true }
            elseif ($cmd -match $aliasNeedle -and (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedle)) { $hit = $true }
        }
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true }
            if ($hit -and -not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                $onFolder = $true
            }
            if ($rootNeedle) {
                $title = $wp.MainWindowTitle
                if ($title -and $title -match $rootNeedle -and
                    ($title -match '\[Claude Server\]' -or $title -match "(?i)\[SSH:\s*${aliasOnlyNeedle}\]")) {
                    $onFolder = $true
                }
            }
        } catch {
            if ($hit -and -not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                $onFolder = $true
            }
        }
    }
    return [pscustomobject]@{ OnFolder = [bool]$onFolder; WindowOpen = [bool]$windowOpen }
}

function Get-RemoteEditorStateExplain {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $bits = @()
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $path = $RemotePath.TrimEnd('/')
    $bits += "target_uri=$uri target_path=$path"

    if ($EditorCmd -ne 'cursor') {
        $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
        $bits += "editor=$EditorCmd matched_procs=$($matched.Count) on_folder=$($matched.Count -gt 0)"
        return ($bits -join ' | ')
    }

    $profileDir = Get-CursorRemoteProfileDir
    $mains = @(Get-CursorMainProfileProcesses)
    $allProfile = @(Get-CursorProfileProcesses)
    $allCursor = @(Invoke-CimCursorProcessQuery -Reason 'state_explain_all')
    $personalCount = @($allCursor | Where-Object {
        $_.CommandLine -and ($_.CommandLine -notmatch [regex]::Escape($profileDir))
    }).Count
    $bits += "cursor_total=$($allCursor.Count) profile_total=$($allProfile.Count) profile_main=$($mains.Count) personal_main=$personalCount"

    $agentHome = Test-RemoteEditorInAgentHome -RemotePath $RemotePath
    $bits += "agent_home=$agentHome"
    if ($agentHome) {
        foreach ($p in $mains) {
            $cmd = $p.CommandLine
            if (-not $cmd) {
                $bits += "agent_reason pid=$($p.ProcessId) empty_cmdline"
                continue
            }
            if ($cmd -notmatch 'folder-uri') {
                $bits += "agent_reason pid=$($p.ProcessId) no_folder_uri_in_cmd"
            } elseif (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath) {
                $bits += "agent_reason pid=$($p.ProcessId) folder_uri_ignored_title_agents"
            }
        }
    }

    $pathNeedle = [regex]::Escape($path)
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($path -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    $onFolder = $false
    foreach ($p in $mains) {
        $cmd = $p.CommandLine
        if (-not $cmd) {
            $bits += "main pid=$($p.ProcessId) empty_cmdline"
            continue
        }
        $uriHit = $cmd -match $uriNeedle
        $aliasPathHit = ($cmd -match $aliasNeedle) -and ($cmd -match $pathNeedle)
        $titleHit = $false
        $title = ''
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            $title = $wp.MainWindowTitle
            if ($rootNeedle -and $title -and $title -match $rootNeedle -and
                ($title -match '\[Claude Server\]' -or $title -match "(?i)\[SSH:\s*${aliasOnlyNeedle}\]")) {
                $titleHit = $true
            }
        } catch { }
        $bits += (
            "main pid=$($p.ProcessId) uri_hit=$uriHit alias_path_hit=$aliasPathHit title_hit=$titleHit " +
            "title=$title cmd=$(Format-EditorProcessCommandLine -CommandLine $cmd -MaxLen 180)"
        )
        if ($uriHit -or $aliasPathHit) {
            if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                $onFolder = $true
            }
        }
        if ($titleHit) { $onFolder = $true }
    }
    if ($mains.Count -eq 0) {
        $bits += 'folder_reason=no_profile_main_process'
    } elseif (-not $onFolder) {
        $bits += 'folder_reason=no_main_process_matched_uri_alias_or_title'
    }
    $bits += "on_folder=$onFolder window_open=$(Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
    return ($bits -join ' | ')
}

function Write-EditorLaunchVerboseState {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$IncludeSnapshot,
        [switch]$ForceLog
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $alwaysLog = $ForceLog -or $Label -match '^EXHAUSTED' -or $script:VerboseLaunch
    if (-not $alwaysLog) {
        $sw.Stop()
        Write-LaunchPerfLog -Mark "verbose_$Label" -Ms $sw.ElapsedMilliseconds -Extra 'skipped=gated'
        return
    }
    Write-EditorLaunchLog "STATE[$Label] $(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    Write-EditorLaunchLog "DIAG[$Label] $(Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    Write-EditorLaunchLog "DETECT[$Label] $(Get-RemoteEditorDetectionDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    if ($EditorCmd -eq 'cursor') {
        Write-EditorLaunchLog "STORAGE[$Label] $(Get-CursorProfileStorageDiag)" 'DEBUG'
    }
    if ($IncludeSnapshot -and ($script:VerboseLaunch -or $ForceLog)) {
        Write-EditorLaunchSnapshot -Label $Label -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    }
    $sw.Stop()
    Write-LaunchPerfLog -Mark "verbose_$Label" -Ms $sw.ElapsedMilliseconds -Extra "snapshot=$([bool]$IncludeSnapshot)"
}

function Test-RemoteEditorInAgentHome {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [string]$RemotePath = ''
    )
    foreach ($p in @(Get-CursorMainProfileProcesses -ProfileDir $ProfileDir)) {
        $cmd = $p.CommandLine
        if (-not $cmd) { continue }
        if ($cmd -notmatch 'folder-uri') { return $true }
        # Cursor 3.x: cmdline has folder-uri but UI stuck on Agents (forum #153009)
        if (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath) { return $true }
    }
    return $false
}

function Write-EditorLaunchLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog $Message $Level
    }
}

function Get-CursorProfileStorageDiag {
    $profileDir = Get-CursorRemoteProfileDir
    $gs = Join-Path $profileDir 'User\globalStorage'
    $ws = Join-Path $profileDir 'User\workspaceStorage'
    $db = Join-Path $gs 'state.vscdb'
    $storageJson = Join-Path $gs 'storage.json'
    $wsCount = 0
    if (Test-Path $ws) { $wsCount = @(Get-ChildItem -Path $ws -Directory -ErrorAction SilentlyContinue).Count }
    $dbSize = if (Test-Path $db) { (Get-Item $db).Length } else { 0 }
    $walSize = if (Test-Path "$db-wal") { (Get-Item "$db-wal").Length } else { 0 }
    $recent = ''
    if (Test-Path $storageJson) {
        try {
            $sj = Get-Content $storageJson -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($sj.'telemetry.machineId') { $recent += " machineId=set" }
        } catch { $recent = 'storage_json_read_error' }
    }
    return (
        "profile_dir=$profileDir globalStorage_exists=$(Test-Path $gs) state_vscdb=$dbSize wal=$walSize " +
        "workspaceStorage_dirs=$wsCount$recent"
    )
}

function Get-ForegroundWindowTitle {
    try {
        if (-not ('Win32.ForegroundWindow' -as [type])) {
            Add-Type -Name ForegroundWindow -Namespace Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
'@ -ErrorAction Stop
        }
        $hwnd = [Win32.ForegroundWindow]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return '' }
        $sb = New-Object System.Text.StringBuilder 512
        [void][Win32.ForegroundWindow]::GetWindowText($hwnd, $sb, $sb.Capacity)
        return $sb.ToString()
    } catch {
        return ''
    }
}

function Get-RemoteEditorLaunchDiag {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    $foregroundTitle = Get-ForegroundWindowTitle
    $mains = if ($EditorCmd -eq 'cursor') { @(Get-CursorMainProfileProcesses) } else { @() }
    $mainSummaries = @()
    foreach ($p in $mains) {
        $cmd = $p.CommandLine
        if (-not $cmd) { $cmd = '' }
        $hasUri = $cmd -match 'folder-uri'
        $hasRemote = $cmd -match '--remote'
        $hasClassic = $cmd -match '--classic'
        $hasPath = $cmd -match [regex]::Escape($RemotePath.TrimEnd('/'))
        if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) + '...' }
        $mainSummaries += "pid=$($p.ProcessId) uri=$hasUri remote=$hasRemote classic=$hasClassic path=$hasPath cmd=$cmd"
    }
    $mainText = if ($mainSummaries.Count -gt 0) { ($mainSummaries -join ' | ') } else { 'none' }
    return (
        "expected_uri=$uri on_folder=$onFolder agent_home=$agentHome window_open=$windowOpen " +
        "foreground_title=$foregroundTitle main_count=$($mains.Count) main=[$mainText]"
    )
}


function Get-CursorProxyLaunchArgs {
    # Chromium/Electron flags: settings.json alone is not enough on Cursor 3.9.x
    # (always-local-singleton can ignore http.proxy / override disableHttp2).
    # --proxy-server + --disable-http2 force the network stack onto our -L SOCKS.
    if (-not $script:SocksProxyPort) { return @() }
    $port = [int]$script:SocksProxyPort
    return @(
        "--proxy-server=socks5://127.0.0.1:$port",
        '--disable-http2'
    )
}

function Get-RemoteEditorLaunchStrategies {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Uri,
        [switch]$NewWindow
    )
    $path = $RemotePath.TrimEnd('/')
    $remoteArg = "ssh-remote+${Alias}"
    $strategies = @()

    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $common = @('--user-data-dir', $profileDir)
        $common += @(Get-CursorProxyLaunchArgs)
        if ($NewWindow) { $common += '--new-window' }
        $strategies += [PSCustomObject]@{
            Name = 'folder-uri-classic'
            Args = $common + @('--classic', '--folder-uri', $Uri)
        }
        $strategies += [PSCustomObject]@{
            Name = 'folder-uri'
            Args = $common + @('--folder-uri', $Uri)
        }
        $strategies += [PSCustomObject]@{
            Name = 'remote-classic'
            Args = $common + @('--classic', '--remote', $remoteArg, $path)
        }
        $strategies += [PSCustomObject]@{
            Name = 'remote'
            Args = $common + @('--remote', $remoteArg, $path)
        }
        return $strategies
    }

    $profileDir = Get-CodeRemoteProfileDir
    $common = @('--user-data-dir', $profileDir)
    if ($NewWindow) { $common += '--new-window' }
    $strategies += [PSCustomObject]@{
        Name = 'folder-uri'
        Args = $common + @('--folder-uri', $Uri)
    }
    $strategies += [PSCustomObject]@{
        Name = 'remote'
        Args = $common + @('--remote', $remoteArg, $path)
    }
    return $strategies
}

function Format-EditorProcessCommandLine {
    param(
        [string]$CommandLine,
        [int]$MaxLen = 220
    )
    if (-not $CommandLine) { return '' }
    if ($CommandLine.Length -le $MaxLen) { return $CommandLine }
    return $CommandLine.Substring(0, $MaxLen) + '...'
}

function Get-RemoteEditorProcessSnapshot {
    param(
        [string]$EditorCmd = 'cursor',
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    $lines = @()
    $lines += "snapshot_ts=$(Get-Date -Format 'o')"
    $lines += "elevated=$(Test-IsElevatedShell) interactive_user=$(Get-InteractiveWindowsUser)"
    if ($Alias -and $RemotePath) {
        $lines += "target_alias=$Alias target_path=$RemotePath target_uri=$(Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath)"
        $lines += "detect_on_folder=$(Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
        if ($EditorCmd -eq 'cursor') {
            $lines += "detect_agent_home=$(Test-RemoteEditorInAgentHome -RemotePath $RemotePath)"
        }
        $lines += "detect_window_open=$(Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
    }

    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $lines += "profile_dir=$profileDir profile_exists=$(Test-Path $profileDir)"
        $settingsPath = Join-Path $profileDir 'User\settings.json'
        $lines += "profile_settings_exists=$(Test-Path $settingsPath)"
        $lines += (Get-CursorProfileStorageDiag)
    }

    $exeName = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $all = @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'process_snapshot')
    $lines += "${exeName}_total=$($all.Count)"
    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $profileCount = @($all | Where-Object { $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($profileDir)) }).Count
        $personalCount = $all.Count - $profileCount
        $lines += "cursor_profile_procs=$profileCount cursor_personal_procs=$personalCount"
    }

    $idx = 0
    foreach ($p in $all) {
        $idx++
        $cmd = $p.CommandLine
        if (-not $cmd) { $cmd = '' }
        $procType = 'unknown'
        if ($cmd -match '--type=renderer') { $procType = 'renderer' }
        elseif ($cmd -match '--type=gpu-process') { $procType = 'gpu' }
        elseif ($cmd -match '--type=utility') { $procType = 'utility' }
        elseif ($cmd -notmatch '--type=') { $procType = 'main' }
        $isMain = ($procType -eq 'main')
        $isProfile = $false
        $hasFolderUri = $false
        $hasRemote = $false
        $hasClassic = $false
        $hasNewWindow = $false
        $hasUserData = $false
        $pathMatch = $false
        $aliasMatch = $false
        if ($EditorCmd -eq 'cursor') {
            $profileDir = Get-CursorRemoteProfileDir
            if ($profileDir -and $cmd -match [regex]::Escape($profileDir)) { $isProfile = $true }
        }
        if ($cmd -match '--folder-uri') { $hasFolderUri = $true }
        if ($cmd -match '--remote') { $hasRemote = $true }
        if ($cmd -match '--classic') { $hasClassic = $true }
        if ($cmd -match '--new-window') { $hasNewWindow = $true }
        if ($cmd -match '--user-data-dir') { $hasUserData = $true }
        if ($RemotePath -and $cmd -match [regex]::Escape($RemotePath.TrimEnd('/'))) { $pathMatch = $true }
        if ($Alias -and $cmd -match [regex]::Escape("ssh-remote+${Alias}")) { $aliasMatch = $true }
        $title = ''
        $hwnd = 0
        if ($isMain) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                $title = $wp.MainWindowTitle
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = 1 }
            } catch { }
        }
        $lines += (
            "${exeName}#$idx pid=$($p.ProcessId) parent=$($p.ParentProcessId) type=$procType main=$isMain profile=$isProfile hwnd=$hwnd " +
            "folder_uri=$hasFolderUri remote=$hasRemote classic=$hasClassic new_window=$hasNewWindow " +
            "user_data=$hasUserData alias_match=$aliasMatch path_match=$pathMatch " +
            "title=$title cmd=$(Format-EditorProcessCommandLine -CommandLine $cmd)"
        )
    }
    return ($lines -join ' | ')
}

function Write-EditorLaunchSnapshot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$EditorCmd,
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    Write-EditorLaunchLog "SNAPSHOT[$Label] $(Get-RemoteEditorProcessSnapshot -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
}

function Stop-CursorServerProfileTreeIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Reason,
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

function Get-RemoteEditorDetectionDiag {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
    $visible = 0
    $hwndZero = 0
    foreach ($p in $matched) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $visible++ } else { $hwndZero++ }
        } catch { $hwndZero++ }
    }
    $profileCount = 0
    $profileVisible = 0
    if ($EditorCmd -eq 'cursor') {
        foreach ($p in @(Get-CursorProfileProcesses)) {
            $profileCount++
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $profileVisible++ }
            } catch { }
        }
    }
    $pathTail = $RemotePath.TrimEnd('/')
    if ($pathTail.Length -gt 48) { $pathTail = '...' + $pathTail.Substring($pathTail.Length - 45) }
    return (
        "matched=$($matched.Count) visible=$visible hwnd0=$hwndZero " +
        "profile=$profileCount profile_visible=$profileVisible path=$pathTail"
    )
}

function Stop-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Path/alias scoped only ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â never kills the whole ClaudeServerCursorProfile tree.
    $procs = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
    Write-EditorLaunchLog (
        "STOP_REMOTE_EDITOR: path_scoped_only alias=$Alias path=$RemotePath matched=$($procs.Count)"
    ) 'INFO'
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog 'STOP_REMOTE_EDITOR: no matching processes' 'DEBUG'
        return
    }

    foreach ($p in $procs) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) {
                $null = $wp.CloseMainWindow()
            }
        } catch { }
    }
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath).Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 500
    }
    foreach ($p in @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Launch-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$KnownOnFolder,
        [switch]$AuthRelaunch
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)
    }

    $script:LaunchCimCallCount = 0
    Clear-CursorProcessCache
    $script:LaunchPerfSw = [System.Diagnostics.Stopwatch]::StartNew()
    $fixes = if ($script:LaunchPerfFixes) { ($script:LaunchPerfFixes -join ',') } else { 'F1,F2,F3,F5,F4' }
    Write-EditorLaunchLog "LAUNCH_PERF_BEGIN fixes=$fixes" 'DEBUG'

    $cli = Get-EditorNativeExe $EditorCmd
    if (-not $cli) {
        Write-EditorLaunchLog 'LAUNCH: editor executable not found' 'ERROR'
        return $false
    }

    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath

    if ($EditorCmd -eq 'cursor') {
        # Must run before Set-CursorProxySettings: it only writes the title/color template
        # when settings.json doesn't exist yet, so on a brand-new profile the proxy merge
        # below would otherwise create a proxy-only file first and permanently skip the template.
        Initialize-CursorServerProfile
        # Write proxy keys to disk, but NEVER soft-stop ClaudeServerCursorProfile for proxy
        # changes. Many windows share one profile; killing the tree closes ALL of them.
        # New launches get --proxy-server/--disable-http2 via Get-CursorProxyLaunchArgs.
        if ($script:SocksProxyPort) {
            try {
                $httpProxyPort = 0
                if ($script:HttpProxyPort) { $httpProxyPort = [int]$script:HttpProxyPort }
                $proxyChanged = [bool](Set-CursorProxySettings -SocksPort ([int]$script:SocksProxyPort) -HttpPort $httpProxyPort)
                if ($proxyChanged) {
                    Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} http={1} (no soft-stop)" -f $script:SocksProxyPort, $httpProxyPort) 'INFO'
                }
            } catch { Write-EditorLaunchLog "CURSOR_PROXY_SET_FAIL: $($_.Exception.Message)" 'WARN' }
        } else {
            try {
                $proxyCleared = [bool](Clear-CursorProxySettings)
                if ($proxyCleared) {
                    Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: preserved_open_windows (no soft-stop)' 'INFO'
                }
            } catch { Write-EditorLaunchLog "CURSOR_PROXY_CLEAR_FAIL: $($_.Exception.Message)" 'WARN' }
        }
    }

    $swEntry = [System.Diagnostics.Stopwatch]::StartNew()
    if ($KnownOnFolder) {
        $onFolder = $true
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms 0 -Extra 'result=True skipped=known_on_folder'
    } else {
        $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        $swEntry.Stop()
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms $swEntry.ElapsedMilliseconds -Extra "result=$onFolder"
    }

    $swAgent = [System.Diagnostics.Stopwatch]::StartNew()
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $swAgent.Stop()
    Write-LaunchPerfLog -Mark 'entry_agent_home' -Ms $swAgent.ElapsedMilliseconds -Extra "result=$agentHome"

    $swProfile = [System.Diagnostics.Stopwatch]::StartNew()
    $hasProfileWindow = if ($EditorCmd -eq 'cursor') { (Get-CursorMainProfileProcesses).Count -gt 0 } else { $false }
    $profileProcCount = if ($EditorCmd -eq 'cursor') { (Get-CursorProfileProcesses).Count } else { 0 }
    $swProfile.Stop()
    Write-LaunchPerfLog -Mark 'entry_profile_counts' -Ms $swProfile.ElapsedMilliseconds -Extra "profile_main=$hasProfileWindow profile_all=$profileProcCount"

    # NEVER soft-stop ClaudeServerCursorProfile for auth. main=1 was a false signal when
    # many windows share one profile (profile_count=24 but only one "main" detected) and
    # wiped every remote window. Auth keys merge in-place into state.vscdb; no kill needed.
    if ($AuthRelaunch -and $EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        $mainCount = @(Get-CursorMainProfileProcesses).Count
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=auth_relaunch_never_kill profile_count={0} main={1}" -f $profileProcCount, $mainCount) 'WARN'
    }

    Write-EditorLaunchLog (
        "LAUNCH_BEGIN: exe=$cli editor=$EditorCmd alias=$Alias path=$RemotePath uri=$uri " +
        "on_folder=$onFolder agent_home=$agentHome profile_main=$hasProfileWindow profile_all=$profileProcCount " +
        "elevated=$(Test-IsElevatedShell) known_on_folder=$KnownOnFolder auth_relaunch=$AuthRelaunch"
    ) 'INFO'

    if ($onFolder -and -not $agentHome) {
        Write-EditorLaunchLog (
            "EDITOR_DECISION: skip_launch reason=already_on_folder on_folder=$onFolder agent_home=$agentHome " +
            "profile_main=$hasProfileWindow profile_all=$profileProcCount"
        ) 'INFO'
        Write-EditorLaunchLog 'LAUNCH_SKIP: already on correct folder - keeping Cursor open' 'INFO'
        $script:LaunchPerfSw.Stop()
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=skip'
        return $true
    }

    if ($script:VerboseLaunch) {
        Write-EditorLaunchVerboseState -Label 'BEGIN' -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
    }

    $useNewWindow = ($agentHome -or $hasProfileWindow)
    Write-EditorLaunchLog "LAUNCH_PLAN: use_new_window=$useNewWindow reason=$(if ($agentHome) { 'agent_home' } elseif ($hasProfileWindow) { 'profile_open' } else { 'cold_start' })" 'INFO'

    if ($EditorCmd -eq 'code') {
        $swInit = [System.Diagnostics.Stopwatch]::StartNew()
        Initialize-CodeServerProfile
        $swInit.Stop()
        Write-LaunchPerfLog -Mark 'launch_init_profile' -Ms $swInit.ElapsedMilliseconds
    }

    # Never force-kill the ClaudeServerCursorProfile tree before launch.
    # Multiple remote projects share one profile -- killing the tree closes ALL Cursor windows.
    # Prefer --new-window (already set via $useNewWindow) and keep other projects open.
    if ($EditorCmd -eq 'cursor' -and ($agentHome -or $useNewWindow) -and ($profileProcCount -gt 0)) {
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=preserve_open_windows profile_count={0} agent_home={1} use_new_window={2}" -f $profileProcCount, $agentHome, $useNewWindow) 'INFO'
        Write-LaunchPerfLog -Mark 'launch_kill_profile' -Ms 0 -Extra 'skipped=preserve_open_windows'
    }

    $swPlan = [System.Diagnostics.Stopwatch]::StartNew()
    $strategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -Uri $uri -NewWindow:$useNewWindow)
    $swPlan.Stop()
    Write-LaunchPerfLog -Mark 'launch_strategies_plan' -Ms $swPlan.ElapsedMilliseconds -Extra "count=$($strategies.Count)"
    Write-EditorLaunchLog "LAUNCH_STRATEGIES: count=$($strategies.Count) names=$($strategies.Name -join ',')" 'INFO'

    $attempt = 0
    $anyStarted = $false
    $script:LastLaunchAttempts = @()
    foreach ($strategy in $strategies) {
        $attempt++
        if ($attempt -gt 1 -and $EditorCmd -eq 'cursor') {
            # Do not wipe the profile on strategy retry -- other open projects must stay alive.
            Write-EditorLaunchLog "LAUNCH_RETRY_NO_KILL: strategy=$($strategy.Name) preserving profile windows" 'DEBUG'
        }

        if ($script:VerboseLaunch) {
            Write-EditorLaunchSnapshot -Label "PRE_ATTEMPT_${attempt}_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }

        Write-EditorLaunchLog "LAUNCH_ATTEMPT: n=$attempt strategy=$($strategy.Name) args=$(Format-ProcessArgumentString -ArgumentList $strategy.Args)" 'INFO'

        $swStart = [System.Diagnostics.Stopwatch]::StartNew()
        if (-not (Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $strategy.Args)) {
            Write-EditorLaunchLog "LAUNCH_FAIL_START: strategy=$($strategy.Name) Start-ProcessAsInteractiveUser returned false" 'ERROR'
            continue
        }
        $swStart.Stop()
        Write-LaunchPerfLog -Mark 'start_process' -Ms $swStart.ElapsedMilliseconds -Extra "strategy=$($strategy.Name)"
        $anyStarted = $true

        $afterFolder = $false
        $afterAgent = $true
        # Poll every 250ms instead of sleeping a full 1s between checks (same 3s total
        # ceiling as before, @(1,2,3)) - a ready window is typically detected within one
        # tick of becoming ready instead of up to ~900ms late, cutting real perceived
        # launch latency without changing the worst-case per-strategy timeout.
        $pollMs = 250
        $pollMaxTicks = 12
        for ($pollTick = 1; $pollTick -le $pollMaxTicks; $pollTick++) {
            Start-Sleep -Milliseconds $pollMs
            Clear-CursorProcessCache
            $afterFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
            $afterAgent = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
            $elapsedMs = $pollTick * $pollMs
            Write-EditorLaunchLog (
                "LAUNCH_POLL: strategy=$($strategy.Name) elapsed=${elapsedMs}ms on_folder=$afterFolder agent_home=$afterAgent"
            ) 'DEBUG'
            Write-LaunchPerfLog -Mark "poll_${elapsedMs}ms" -Ms $elapsedMs -Extra "on_folder=$afterFolder strategy=$($strategy.Name)"

            if ($afterFolder -and -not $afterAgent) {
                # Return on first on_folder hit - the extra recheck added latency without
                # preventing false positives in practice.
                Write-EditorLaunchLog "LAUNCH_OK: strategy=$($strategy.Name) attempt=$attempt" 'INFO'
                $script:LastLaunchAttempts += "${attempt}:$($strategy.Name):folder=$afterFolder:agent=$afterAgent"
                $script:LaunchPerfSw.Stop()
                Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra "path=ok strategy=$($strategy.Name)"
                return $true
            }

            if ($script:VerboseLaunch -and $pollTick -eq $pollMaxTicks) {
                Write-EditorLaunchVerboseState -Label "POLL_${elapsedMs}ms_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
            }
        }

        Write-EditorLaunchLog (
            "LAUNCH_ATTEMPT_RESULT: n=$attempt strategy=$($strategy.Name) on_folder=$afterFolder agent_home=$afterAgent " +
            "$(Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
        ) 'INFO'
        $script:LastLaunchAttempts += "${attempt}:$($strategy.Name):folder=$afterFolder:agent=$afterAgent"
        if ($script:VerboseLaunch) {
            Write-EditorLaunchVerboseState -Label "RESULT_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
        }

        Write-EditorLaunchLog "LAUNCH_RETRY: strategy=$($strategy.Name) did not reach target folder - next strategy" 'WARN'
    }

    Write-EditorLaunchVerboseState -Label 'EXHAUSTED' -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot -ForceLog
    $script:LaunchPerfSw.Stop()
    if (-not $anyStarted) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: all strategies failed to start process' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail'
        return $false
    }

    Clear-CursorProcessCache
    $profileProcs = @(Get-EditorProfileProcessesForLaunch -EditorCmd $EditorCmd -ForceRefresh)
    if ($profileProcs.Count -eq 0) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_process'
        return $false
    }

    $mainCount = if ($EditorCmd -eq 'cursor') {
        @(Get-CursorMainProfileProcesses).Count
    } else {
        @($profileProcs | Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') }).Count
    }
    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath

    Write-EditorLaunchLog 'LAUNCH_WARN: process started but folder workspace not detected - press O to retry' 'WARN'
    if ($mainCount -eq 0) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process main_count=0' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_main'
        return $false
    }
    if (-not $windowOpen) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_window' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_window'
        return $false
    }

    Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_not_on_folder'
    return $false
}

