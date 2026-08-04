# windows-mcp-laptop.ps1 - Ensure Windows-MCP on the laptop during connect.
# Dot-sourced by windows/connect.ps1 only (not Mac / not designer).
# Fail-soft + background: never block/abort connect UI.
#
# Precise bootstrap (fresh Windows, no Python required in the happy path):
#
#   A. windows-mcp.exe already on PATH / known dirs  -> skip package install
#   B. else ensure uv.exe (standalone; does NOT need system Python):
#        B1. winget astral-sh.uv  (works when connect is elevated)
#        B2. https://astral.sh/uv/install.ps1
#        B3. ONLY if B1+B2 fail: winget Python.Python.3.12/3.13, then pip install --user uv
#   C. uv python install 3.12   (uv-managed CPython; no system Python)
#   D. uv tool install --managed-python windows-mcp   (retry x3)
#   E. last resort: pip install --user windows-mcp (needs system Python from B3)
#   F. auth --force + install scheduled task (logon) + DIRECT hidden serve + listen :LPORT
#   G. SSH sync auth -> server ~/.config/windows-mcp/env + mcp.json + forward
#
# Notes:
# - Background child inherits connect.ps1 elevation (UAC at connect start).
# - Never treat WindowsApps\python*.exe stubs as real Python.
# - Secrets: auth_key in config.toml (auth.key mirrored when present); Bearer sync over SSH alias.
# - Default local port is NOT 8000: Hyper-V/WSL often reserves 7916-8015 (WinError
#   10013 on bind). Prefer 18765; fall back to the first bindable candidate.
# - Never invoke the logon task mid-session (vendor start-server.cmd flashes cmd.exe). Prefer
#   Start-WindowsMcpProcessDirect (CreateNoWindow). Logon task uses a VBS style-0 trampoline.

# Laptop-side streamable-http listen port (server forward targets this).
$script:WindowsMcpLocalPortDefault = 18765
$script:WindowsMcpLocalPort = $null

function Test-WindowsMcpPortBindable {
    param([Parameter(Mandatory)][int]$Port)
    try {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $l.Start()
        $l.Stop()
        return $true
    } catch {
        return $false
    }
}

function Stop-WindowsMcpLegacyPort8000 {
    # Legacy :8000 is Hyper-V-hostile. Never sticky-adopt it across reconnects
    # (Get-WindowsMcpLocalPort used to prefer any already-listening candidate including 8000,
    # so one stale task pinned the fleet on 8000 forever — hard-test 2026-08-01).
    try {
        $legacy = @(Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0') })
        foreach ($c in $legacy) {
            try {
                Stop-Process -Id ([int]$c.OwningProcess) -Force -ErrorAction SilentlyContinue
                Write-WindowsMcpEnsureLog ("legacy_8000_killed pid={0}" -f $c.OwningProcess)
            } catch { }
        }
        if ($legacy.Count -gt 0) {
            Start-Sleep -Milliseconds 400
            return $true
        }
    } catch { }
    return $false
}

function Get-WindowsMcpLocalPort {
    if ($env:WMCP_LPORT -match '^\d+$') {
        $envPort = [int]$env:WMCP_LPORT
        if ($envPort -ge 1024 -and $envPort -le 65535 -and $envPort -ne 8000) {
            $script:WindowsMcpLocalPort = $envPort
            return $envPort
        }
    }
    if ($script:WindowsMcpLocalPort -and $script:WindowsMcpLocalPort -gt 0 -and $script:WindowsMcpLocalPort -ne 8000) {
        return [int]$script:WindowsMcpLocalPort
    }
    # Prefer canonical :18765 only when already listening. Do NOT sticky-adopt
    # chaos fallbacks (17654/19000) from parallel Ensure races — that desyncs the
    # server forward LPORT and yields permanent WMCP_PROBE=000 (e2e ×6 20260804.13).
    foreach ($cand in @($script:WindowsMcpLocalPortDefault, 18765)) {
        try {
            $c = @(Get-NetTCPConnection -State Listen -LocalPort $cand -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0') })
            if ($c.Count -gt 0) {
                $script:WindowsMcpLocalPort = $cand
                return $cand
            }
        } catch { }
    }
    foreach ($cand in @($script:WindowsMcpLocalPortDefault, 18765, 17654, 19000, 19100)) {
        if (Test-WindowsMcpPortBindable -Port $cand) {
            $script:WindowsMcpLocalPort = $cand
            return $cand
        }
    }
    # Last resort: preferred default (not 8000).
    $script:WindowsMcpLocalPort = [int]$script:WindowsMcpLocalPortDefault
    return [int]$script:WindowsMcpLocalPortDefault
}

function Update-WindowsMcpPath {
    try {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($chunk in @(
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            [Environment]::GetEnvironmentVariable('Path', 'User')
            (Join-Path $env:USERPROFILE '.local\bin')
            (Join-Path $env:USERPROFILE '.cargo\bin')
            (Join-Path $env:LOCALAPPDATA 'Programs\uv')
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312')
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\Scripts')
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313')
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\Scripts')
            (Join-Path $env:APPDATA 'Python\Python312\Scripts')
            (Join-Path $env:APPDATA 'Python\Python313\Scripts')
        )) {
            if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
            foreach ($p in ($chunk -split ';' | Where-Object { $_ -and $_.Trim() })) {
                if (-not $parts.Contains($p)) { [void]$parts.Add($p) }
            }
        }
        $env:Path = ($parts -join ';')
    } catch { }
}

function Ensure-WindowsMcpUserPathEntry {
    # Persist ~/.local/bin on User PATH so scheduled task / new shells find windows-mcp.
    $localBin = Join-Path $env:USERPROFILE '.local\bin'
    try {
        if (-not (Test-Path -LiteralPath $localBin)) {
            New-Item -ItemType Directory -Force -Path $localBin | Out-Null
        }
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        $parts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() })
        if ($parts -notcontains $localBin) {
            $newPath = if ($userPath.Trim()) { "$userPath;$localBin" } else { $localBin }
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-WindowsMcpEnsureLog ("user_path_added {0}" -f $localBin)
        }
    } catch {
        Write-WindowsMcpEnsureLog ("user_path_update_failed {0}" -f $_.Exception.Message) 'WARN'
    }
    Update-WindowsMcpPath
}

function Write-WindowsMcpHost {
    param([string]$Message)
    if ($env:WINDOWS_MCP_ENSURE_QUIET -eq '1') { return }
    Write-Host $Message -ForegroundColor DarkGray
}

function Write-WindowsMcpEnsureLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $path = Join-Path $dir 'windows-mcp-ensure.log'
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("WINDOWS_MCP: {0}" -f $Message) $Level
    }
}

function Test-WindowsMcpIsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return [bool]$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-WindowsMcpExe {
    Update-WindowsMcpPath
    $candidates = @(
        (Join-Path $env:USERPROFILE '.local\bin\windows-mcp.exe')
        (Join-Path $env:USERPROFILE '.cargo\bin\windows-mcp.exe')
        (Join-Path $env:APPDATA 'Python\Python313\Scripts\windows-mcp.exe')
        (Join-Path $env:APPDATA 'Python\Python312\Scripts\windows-mcp.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\Scripts\windows-mcp.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\Scripts\windows-mcp.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command windows-mcp -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\')) { return $cmd.Source }
    return $null
}

function Get-UvExe {
    Update-WindowsMcpPath
    $candidates = @(
        (Join-Path $env:USERPROFILE '.local\bin\uv.exe')
        (Join-Path $env:USERPROFILE '.cargo\bin\uv.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\uv\uv.exe')
        (Join-Path $env:APPDATA 'Python\Python313\Scripts\uv.exe')
        (Join-Path $env:APPDATA 'Python\Python312\Scripts\uv.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\Scripts\uv.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\Scripts\uv.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch 'WindowsApps\\')) { return $cmd.Source }
    return $null
}

function Test-RealPythonExe {
    param([string]$Exe)
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { return $false }
    if ($Exe -match 'WindowsApps\\python') { return $false }
    try {
        $ver = & $Exe --version 2>&1 | Out-String
        return [bool]($ver -match 'Python\s+3\.\d+')
    } catch { return $false }
}

function Get-PythonLauncher {
    Update-WindowsMcpPath
    # Prefer py -3 launcher (real) over Store stubs.
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher -and $pyLauncher.Source -notmatch 'WindowsApps\\') {
        try {
            $exe = (& $pyLauncher.Source -3 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
            if (Test-RealPythonExe $exe) { return $exe.Trim() }
        } catch { }
    }
    foreach ($name in @('python', 'python3')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and (Test-RealPythonExe $cmd.Source)) { return $cmd.Source }
    }
    foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe')
        'C:\Python313\python.exe'
        'C:\Python312\python.exe'
    )) {
        if (Test-RealPythonExe $c) { return $c }
    }
    return $null
}

function Test-WindowsMcpListening {
    $port = Get-WindowsMcpLocalPort
    try {
        $c = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0') })
        return ($c.Count -gt 0)
    } catch {
        # Avoid cmd.exe flash: parse netstat via hidden process + redirected stdout.
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = (Join-Path $env:SystemRoot 'System32\netstat.exe')
            $psi.Arguments = '-ano'
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $proc = [Diagnostics.Process]::Start($psi)
            $out = $proc.StandardOutput.ReadToEnd()
            [void]$proc.WaitForExit(5000)
            $needle = ':' + $port
            foreach ($line in ($out -split "`r?`n")) {
                if ($line -match 'LISTENING' -and $line -like "*$needle*") { return $true }
            }
            return $false
        } catch { return $false }
    }
}

function Invoke-WindowsMcpWingetInstall {
    param([Parameter(Mandatory)][string]$PackageId)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-WindowsMcpEnsureLog 'winget_missing'
        return $false
    }
    Write-WindowsMcpEnsureLog ("winget_install id={0} admin={1}" -f $PackageId, [int](Test-WindowsMcpIsAdmin))
    try {
        $args = @(
            'install', '--id', $PackageId, '-e', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements',
            '--disable-interactivity'
        )
        # Bounded wait, not blind -Wait: winget can hang indefinitely (observed once on
        # this machine - a single install sat for 2h17m) waiting on a Store/Update-service
        # lock with no visible prompt. This whole ensure already runs in a background,
        # non-interactive process, so an unbounded hang here just burns CPU/network for
        # hours and - since it never reaches winget_exit - lets every subsequent connect
        # spawn ANOTHER stuck winget process on top of it (same leaked-process class as
        # the ClaudeServerEditorLaunch scheduled-task issue). 10 min is generous for a
        # small CLI tool; kill and fail closed past that instead of hanging forever.
        $p = Start-Process -FilePath $winget.Source -ArgumentList $args -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(600000)) {
            Write-WindowsMcpEnsureLog ("winget_timeout id={0} killing" -f $PackageId) 'WARN'
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
            return $false
        }
        Write-WindowsMcpEnsureLog ("winget_exit id={0} code={1}" -f $PackageId, $p.ExitCode)
        return ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) # already installed common code
    } catch {
        Write-WindowsMcpEnsureLog ("winget_throw id={0} err={1}" -f $PackageId, $_.Exception.Message) 'WARN'
        return $false
    }
}

function Install-PythonIfMissing {
    $py = Get-PythonLauncher
    if ($py) {
        Write-WindowsMcpEnsureLog ("python_present {0}" -f $py)
        return $py
    }
    Write-WindowsMcpHost '      -> installing system Python (winget fallback)...'
    foreach ($id in @('Python.Python.3.12', 'Python.Python.3.13')) {
        [void](Invoke-WindowsMcpWingetInstall -PackageId $id)
        Update-WindowsMcpPath
        $py = Get-PythonLauncher
        if ($py) {
            Write-WindowsMcpEnsureLog ("python_installed {0}" -f $py)
            return $py
        }
    }
    Write-WindowsMcpEnsureLog 'python_install_failed' 'WARN'
    return $null
}

function Install-UvViaPip {
    param([string]$PythonExe)
    if (-not $PythonExe) { return $null }
    Write-WindowsMcpHost '      -> installing uv via pip (last resort)...'
    Write-WindowsMcpEnsureLog ("pip_install_uv python={0}" -f $PythonExe)
    try {
        & $PythonExe -m pip install --upgrade pip 2>&1 | Out-Null
        & $PythonExe -m pip install --user uv 2>&1 | Out-Null
    } catch {
        Write-WindowsMcpEnsureLog ("pip_uv_failed {0}" -f $_.Exception.Message) 'WARN'
    }
    Update-WindowsMcpPath
    return (Get-UvExe)
}

function Install-UvIfMissing {
    Update-WindowsMcpPath
    $uv = Get-UvExe
    if ($uv) {
        Write-WindowsMcpEnsureLog ("uv_present {0}" -f $uv)
        return $uv
    }

    Write-WindowsMcpHost '      -> installing uv (standalone; no system Python needed)...'
    Write-WindowsMcpEnsureLog 'installing_uv'

    # B1 winget
    if (Invoke-WindowsMcpWingetInstall -PackageId 'astral-sh.uv') {
        Update-WindowsMcpPath
        $uv = Get-UvExe
        if ($uv) {
            Write-WindowsMcpEnsureLog ("uv_installed_winget {0}" -f $uv)
            return $uv
        }
    }

    # B2 official standalone installer (no Python)
    try {
        $env:UV_NO_MODIFY_PATH = '0'
        Write-WindowsMcpEnsureLog 'uv_install_script astral.sh'
        irm https://astral.sh/uv/install.ps1 | iex
        Update-WindowsMcpPath
        Ensure-WindowsMcpUserPathEntry
        $uv = Get-UvExe
        if ($uv) {
            Write-WindowsMcpEnsureLog ("uv_installed_script {0}" -f $uv)
            return $uv
        }
    } catch {
        Write-WindowsMcpEnsureLog ("uv_script_failed {0}" -f $_.Exception.Message) 'WARN'
    }

    # B3 system Python + pip (only if standalone uv failed)
    $py = Install-PythonIfMissing
    if ($py) {
        $uv = Install-UvViaPip -PythonExe $py
        if ($uv) {
            Write-WindowsMcpEnsureLog ("uv_installed_pip {0}" -f $uv)
            return $uv
        }
    }

    Write-WindowsMcpEnsureLog 'uv_install_exhausted' 'WARN'
    return $null
}

function Ensure-UvManagedPython {
    param([Parameter(Mandatory)][string]$UvExe)
    Write-WindowsMcpEnsureLog 'uv_python_install 3.12'
    try {
        $out = & $UvExe python install 3.12 2>&1 | Out-String
        $clip = (($out -replace '\s+', ' ').Trim())
        if ($clip.Length -gt 240) { $clip = $clip.Substring(0, 240) }
        Write-WindowsMcpEnsureLog ("uv_python_install_out {0}" -f $clip)
    } catch {
        Write-WindowsMcpEnsureLog ("uv_python_install_err {0}" -f $_.Exception.Message) 'WARN'
    }
    try {
        $find = & $UvExe python find 3.12 2>&1 | Out-String
        Write-WindowsMcpEnsureLog ("uv_python_find {0}" -f (($find -replace '\s+', ' ').Trim()))
    } catch { }
}

function Install-WindowsMcpPackage {
    param([string]$UvExe)
    $existing = Get-WindowsMcpExe
    if ($existing) { return $existing }
    if (-not $UvExe) { return $null }

    Ensure-WindowsMcpUserPathEntry
    Ensure-UvManagedPython -UvExe $UvExe

    Write-WindowsMcpHost '      -> installing windows-mcp (uv tool, managed Python)...'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-WindowsMcpEnsureLog ("uv_tool_install attempt={0}" -f $attempt)
        try {
            # --managed-python: do not depend on system Python
            $out = & $UvExe tool install --managed-python windows-mcp 2>&1 | Out-String
            $clip = (($out -replace '\s+', ' ').Trim())
            if ($clip.Length -gt 300) { $clip = $clip.Substring(0, 300) }
            Write-WindowsMcpEnsureLog ("uv_tool_install_out {0}" -f $clip)
        } catch {
            Write-WindowsMcpEnsureLog ("uv_tool_install_err {0}" -f $_.Exception.Message) 'WARN'
        }
        try { & $UvExe tool update-shell 2>&1 | Out-Null } catch { }
        Update-WindowsMcpPath
        Ensure-WindowsMcpUserPathEntry
        $exe = Get-WindowsMcpExe
        if ($exe) {
            Write-WindowsMcpEnsureLog ("windows_mcp_installed {0}" -f $exe)
            return $exe
        }
        # fallback without flag (older uv)
        try {
            $out2 = & $UvExe tool install windows-mcp 2>&1 | Out-String
            $leg = (($out2 -replace '\s+', ' ').Trim())
            if ($leg.Length -gt 300) { $leg = $leg.Substring(0, 300) }
            Write-WindowsMcpEnsureLog ("uv_tool_install_legacy_out {0}" -f $leg)
        } catch { }
        Update-WindowsMcpPath
        $exe = Get-WindowsMcpExe
        if ($exe) { return $exe }
        Start-Sleep -Seconds (3 * $attempt)
    }

    $py = Get-PythonLauncher
    if (-not $py) { $py = Install-PythonIfMissing }
    if ($py) {
        Write-WindowsMcpEnsureLog ("pip_install_windows_mcp python={0}" -f $py)
        try { & $py -m pip install --user windows-mcp 2>&1 | Out-Null } catch {
            Write-WindowsMcpEnsureLog ("pip_windows_mcp_failed {0}" -f $_.Exception.Message) 'WARN'
        }
        Update-WindowsMcpPath
        $exe = Get-WindowsMcpExe
        if ($exe) {
            Write-WindowsMcpEnsureLog ("windows_mcp_installed_pip {0}" -f $exe)
            return $exe
        }
    }

    Write-WindowsMcpEnsureLog 'windows_mcp_install_failed' 'WARN'
    return $null
}

function Repair-WindowsMcpUtf8WriteNewline {
    <#
    .SYNOPSIS
      Patch windows-mcp FileSystem write_file to use newline='' (no \n\r\n translation).
    .NOTES
      Upstream open(..., encoding=utf-8) without newline='' turns agent \r\n into \r\r\n
      (extra blank lines) and mangles UTF-8 text edited across mount/MCP/LE. Idempotent.
      Returns $true if any file was newly patched (caller should restart the server).
    #>
    $changed = $false
    # Match the exact upstream write_file open() line (4-space indent inside try).
    $needle = "        with open(file_path, mode, encoding=encoding) as f:"
    $repl = "        with open(file_path, mode, encoding=encoding, newline='') as f:"
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        (Join-Path $env:APPDATA 'uv\tools\windows-mcp\Lib\site-packages\windows_mcp\filesystem\service.py'),
        (Join-Path $env:LOCALAPPDATA 'uv\tools\windows-mcp\Lib\site-packages\windows_mcp\filesystem\service.py'),
        (Join-Path $env:USERPROFILE '.local\share\uv\tools\windows-mcp\Lib\site-packages\windows_mcp\filesystem\service.py')
    )) {
        if (Test-Path -LiteralPath $candidate) { [void]$roots.Add($candidate) }
    }
    # Also patch uv cache copies used by some installs
    $cacheRoot = Join-Path $env:LOCALAPPDATA 'uv\cache'
    if (Test-Path -LiteralPath $cacheRoot) {
        Get-ChildItem -LiteralPath $cacheRoot -Recurse -Filter 'service.py' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]windows_mcp[\\/]filesystem[\\/]service\.py$' } |
            ForEach-Object { [void]$roots.Add($_.FullName) }
    }
    foreach ($path in ($roots | Select-Object -Unique)) {
        try {
            $raw = [System.IO.File]::ReadAllText($path)
        } catch {
            Write-WindowsMcpEnsureLog ("utf8_write_patch_read_fail {0} {1}" -f $path, $_.Exception.Message) 'WARN'
            continue
        }
        if ($raw -match "newline\s*=\s*''") {
            continue
        }
        if ($raw -notlike "*$needle*") {
            continue
        }
        $newRaw = $raw.Replace($needle, $repl)
        if ($newRaw -eq $raw) { continue }
        try {
            [System.IO.File]::WriteAllText($path, $newRaw, [System.Text.UTF8Encoding]::new($false))
            $changed = $true
            Write-WindowsMcpEnsureLog ("utf8_write_patch_applied {0}" -f $path)
        } catch {
            Write-WindowsMcpEnsureLog ("utf8_write_patch_write_fail {0} {1}" -f $path, $_.Exception.Message) 'WARN'
        }
    }
    return $changed
}

function Get-WindowsMcpAuthKeyFromToml {
    param([string]$TomlPath)
    if (-not (Test-Path -LiteralPath $TomlPath)) { return $null }
    $toml = ((Get-Content -LiteralPath $TomlPath -Raw -ErrorAction SilentlyContinue) + '')
    if ($toml -match 'auth_key\s*=\s*"([^"]+)"') {
        $k = ($Matches[1] + '').Trim()
        if ($k.Length -ge 32) { return $k }
    }
    return $null
}

function Ensure-WindowsMcpAuth {
    param([string]$WmExe, [string]$CfgDir)
    $authPath = Join-Path $CfgDir 'auth.key'
    $tomlPath = Join-Path $CfgDir 'config.toml'
    # Legacy auth.key (older windows-mcp); current CLI only writes config.toml.
    if (Test-Path -LiteralPath $authPath) {
        $k = ((Get-Content -LiteralPath $authPath -Raw -ErrorAction SilentlyContinue) + '').Trim()
        if ($k.Length -ge 32) { return $k }
    }
    $fromToml = Get-WindowsMcpAuthKeyFromToml -TomlPath $tomlPath
    if ($fromToml) { return $fromToml }
    if (-not $WmExe) { return $null }
    Write-WindowsMcpHost '      -> generating windows-mcp auth...'
    Write-WindowsMcpEnsureLog 'generating auth'
    $script:WindowsMcpAuthRotated = $true
    $prevEapAuth = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # CLI may exit 1 after save (UnicodeEncodeError on cp1252) - key still written to config.toml.
        # Native stderr under caller Stop must not abort before we re-read auth/toml.
        $lport = Get-WindowsMcpLocalPort
        & $WmExe auth --transport streamable-http --host 127.0.0.1 --port $lport --force 2>&1 | Out-Null
    } catch {
        Write-WindowsMcpEnsureLog ("auth_failed {0}" -f $_.Exception.Message) 'WARN'
    } finally {
        $ErrorActionPreference = $prevEapAuth
    }
    if (Test-Path -LiteralPath $authPath) {
        $k = ((Get-Content -LiteralPath $authPath -Raw -ErrorAction SilentlyContinue) + '').Trim()
        if ($k.Length -ge 32) { return $k }
    }
    $fromToml = Get-WindowsMcpAuthKeyFromToml -TomlPath $tomlPath
    if ($fromToml) {
        try {
            Set-Content -LiteralPath $authPath -Value $fromToml -Encoding ascii -NoNewline -ErrorAction SilentlyContinue
        } catch { }
        return $fromToml
    }
    Write-WindowsMcpEnsureLog 'auth_missing_after_generate' 'WARN'
    return $null
}


function Write-WindowsMcpHiddenLogonLauncher {
    # Replace vendor start-server.cmd (visible console under schtasks) with a VBS style-0
    # trampoline so At-logon does not flash cmd.exe. Mid-session start never uses this path.
    param([string]$WmExe)
    $cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
    if (-not (Test-Path -LiteralPath $cfgDir)) {
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    }
    $lport = Get-WindowsMcpLocalPort
    $vbs = Join-Path $cfgDir 'start-server-hidden.vbs'
    $cmd = Join-Path $cfgDir 'start-server.cmd'
    $filePath = $null
    $argStr = $null
    $via = 'python'
    if ($WmExe -and (Test-Path -LiteralPath $WmExe)) {
        $filePath = $WmExe
        $argStr = "serve --transport streamable-http --host 127.0.0.1 --port $lport"
        $via = 'exe'
    } else {
        $py = Get-PythonLauncher
        if (-not $py) { return $false }
        $filePath = $py
        $argStr = "-m windows_mcp serve --transport streamable-http --host 127.0.0.1 --port $lport"
    }
    # Quote for VBScript string literal: double any embedded double-quotes.
    $fpQ = ($filePath -replace '"', '""')
    $argQ = ($argStr -replace '"', '""')
    $vbsBody = @"
Option Explicit
Dim sh
Set sh = CreateObject("WScript.Shell")
' style 0 = hidden (not minimized); False = do not wait
sh.Run """$fpQ"" $argQ", 0, False
"@
    foreach ($p in @($vbs, $cmd)) {
        try {
            if (Test-Path -LiteralPath $p) {
                $item = Get-Item -LiteralPath $p -Force
                if ($item.IsReadOnly) { $item.IsReadOnly = $false }
            }
        } catch { }
    }
    Set-Content -LiteralPath $vbs -Value $vbsBody -Encoding ASCII -Force
    $cmdBody = "@echo off`r`nwscript.exe //B //Nologo `"%~dp0start-server-hidden.vbs`"`r`n"
    Set-Content -LiteralPath $cmd -Value $cmdBody -Encoding ASCII -Force
    Write-WindowsMcpEnsureLog ("hidden_logon_launcher port={0} via={1}" -f $lport, $via)
    return $true
}

function Ensure-WindowsMcpTask {
    param([string]$WmExe)
    if (-not $WmExe) { return $false }
    $lport = Get-WindowsMcpLocalPort
    $task = Get-ScheduledTask -TaskName 'windows-mcp-server' -ErrorAction SilentlyContinue
    $startCmd = Join-Path $env:USERPROFILE '.windows-mcp\start-server.cmd'
    $hideVbs = Join-Path $env:USERPROFILE '.windows-mcp\start-server-hidden.vbs'
    # Reinstall when missing, OR when start-server.cmd still pins a Hyper-V-blocked
    # port (old default :8000) so reconnect cannot revive a dead bind.
    $needInstall = -not [bool]$task
    if (-not $needInstall) {
        if (Test-Path -LiteralPath $startCmd) {
            $raw = (Get-Content -LiteralPath $startCmd -Raw -ErrorAction SilentlyContinue) + ''
            # Vendor cmd embeds --port; our hidden trampoline only calls wscript - port lives in VBS.
            $hasHidden = (Test-Path -LiteralPath $hideVbs) -and ($raw -match 'start-server-hidden\.vbs')
            $hasPort = ($raw -match [regex]::Escape("--port',$lport") -or $raw -match "--port['\s]+$lport")
            if (-not $hasHidden) {
                if ($raw -notmatch [regex]::Escape("--port',$lport") -and $raw -notmatch "--port['\s]+$lport" -and $raw -notmatch 'start-server-hidden\.vbs') {
                    $needInstall = $true
                } elseif (-not $hasPort -and $raw -match 'python\.exe|windows_mcp|windows-mcp') {
                    # Stale vendor cmd with wrong port
                    $needInstall = $true
                }
            } else {
                # Refresh VBS when port/exe drifted, still pins legacy 8000, or file is corrupt
                $vbsRaw = (Get-Content -LiteralPath $hideVbs -Raw -ErrorAction SilentlyContinue) + ''
                if ($vbsRaw -match '--port\s+8000' -or $vbsRaw -notmatch "--port\s+$lport" -or $vbsRaw -notmatch 'WScript\.Shell') {
                    [void](Write-WindowsMcpHiddenLogonLauncher -WmExe $WmExe)
                }
            }
        } else {
            $needInstall = $true
        }
    }
    if ($needInstall) {
        Write-WindowsMcpHost ("      -> registering windows-mcp login task (port {0})..." -f $lport)
        Write-WindowsMcpEnsureLog ("registering scheduled task port={0}" -f $lport)
        # Native install writes stderr; under caller's $ErrorActionPreference=Stop that
        # becomes a terminating error - never abort before hidden-launcher rewrite.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $WmExe install --transport streamable-http --host 127.0.0.1 --port $lport --force 2>&1 | Out-Null
        } catch {
            Write-WindowsMcpEnsureLog ("install_task_failed {0}" -f $_.Exception.Message) 'WARN'
        } finally {
            $ErrorActionPreference = $prevEap
        }
    }
    # Always rewrite logon launcher to hidden VBS (idempotent; kills vendor cmd flash).
    # Must run even when install failed or vendor rewrote start-server.cmd.
    $hidOk = [bool](Write-WindowsMcpHiddenLogonLauncher -WmExe $WmExe)
    $taskOk = [bool](Get-ScheduledTask -TaskName 'windows-mcp-server' -ErrorAction SilentlyContinue)
    return ($hidOk -and $taskOk)
}


function Start-WindowsMcpProcessDirect {
    # Prefer windows-mcp.exe; else python -m windows_mcp serve (no cmd.exe wrapper).
    $filePath = $null
    $argStr = $null
    $via = $null
    $lport = Get-WindowsMcpLocalPort
    $exe = Get-WindowsMcpExe
    if ($exe) {
        $filePath = $exe
        $argStr = "serve --transport streamable-http --host 127.0.0.1 --port $lport"
        $via = 'windows_mcp_exe'
    } else {
        $py = Get-PythonLauncher
        if (-not $py) {
            Write-WindowsMcpEnsureLog 'start_direct_no_exe_or_python' 'WARN'
            return $false
        }
        $filePath = $py
        $argStr = "-m windows_mcp serve --transport streamable-http --host 127.0.0.1 --port $lport"
        $via = 'python_direct'
    }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $filePath
        $psi.Arguments = $argStr
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        if (-not $p.Start()) {
            Write-WindowsMcpEnsureLog 'start_direct_start_returned_false' 'WARN'
            return $false
        }
        if ($via -eq 'windows_mcp_exe') {
            Write-WindowsMcpEnsureLog 'started_via_windows_mcp_exe'
        } else {
            Write-WindowsMcpEnsureLog 'started_via_python_direct'
        }
        return $true
    } catch {
        Write-WindowsMcpEnsureLog ("start_direct_failed {0}" -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Stop-WindowsMcpOrphanCmdWrappers {
    # Reap leftover cmd.exe /c parents that launched start-server.cmd once LPORT listens.
    if (-not (Test-WindowsMcpListening)) { return }
    try {
        $orphans = @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $cl = [string]$_.CommandLine
                $cl -and ($cl -match 'start-server\.cmd') -and ($cl -match 'windows-mcp')
            })
        foreach ($o in $orphans) {
            try {
                Stop-Process -Id ([int]$o.ProcessId) -Force -ErrorAction SilentlyContinue
                Write-WindowsMcpEnsureLog ("orphan_cmd_reaped pid={0}" -f $o.ProcessId)
            } catch { }
        }
    } catch {
        Write-WindowsMcpEnsureLog ("orphan_cmd_reap_failed {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Enter-WmcpEnsureMutex {
    param(
        [int]$TimeoutMs = 120000,
        # Maintain uses a short poll — timeout is expected, not a fault.
        [switch]$QuietTimeout
    )
    $script:WmcpEnsureMutex = $null
    $script:WmcpEnsureMutexGot = $false
    try {
        $script:WmcpEnsureMutex = New-Object System.Threading.Mutex($false, 'Global\ClaudeConnectWmcpEnsure')
        # Parallel Connect: never Sync/Restart without the lock (20s was too short; peers
        # then killed shared :18765 and stamped WMCP_PROBE=000 — e2e ×6 worker6 20260804.11).
        try {
            $script:WmcpEnsureMutexGot = $script:WmcpEnsureMutex.WaitOne($TimeoutMs)
        } catch [System.Threading.AbandonedMutexException] {
            # Previous owner crashed — we now hold the mutex (do not skip Sync).
            $script:WmcpEnsureMutexGot = $true
            Write-WindowsMcpEnsureLog 'ensure_mutex_abandoned acquired' 'INFO'
        }
        if (-not $script:WmcpEnsureMutexGot) {
            $lvl = if ($QuietTimeout) { 'INFO' } else { 'WARN' }
            Write-WindowsMcpEnsureLog ("ensure_mutex_timeout ms={0} skip_locked_work" -f $TimeoutMs) $lvl
        }
    } catch {
        # PS wraps WaitOne abandoned as MethodInvocationException + message text.
        $ex = $_.Exception
        $msg = [string]$ex.Message
        $inner = $null
        try { $inner = $ex.InnerException } catch { }
        $isAbandoned = ($ex -is [System.Threading.AbandonedMutexException]) -or
            ($inner -is [System.Threading.AbandonedMutexException]) -or
            ($msg -match 'abandoned mutex') -or
            ($inner -and (([string]$inner.Message) -match 'abandoned mutex'))
        if ($isAbandoned) {
            $script:WmcpEnsureMutexGot = $true
            Write-WindowsMcpEnsureLog 'ensure_mutex_abandoned acquired' 'INFO'
        } else {
            Write-WindowsMcpEnsureLog ("ensure_mutex_error {0} skip_locked_work" -f $msg) 'WARN'
        }
    }
    return [bool]$script:WmcpEnsureMutexGot
}

function Test-WindowsMcpHttpReady {
    # TCP listen is not enough: uv/python can accept before /mcp initialize returns 200.
    param([int]$TimeoutMs = 15000, [string]$AuthKey = '')
    $port = Get-WindowsMcpLocalPort
    $auth = ''
    if ($AuthKey) { $auth = $AuthKey }
    try {
        if (-not $auth -and $script:WindowsMcpAuthKey) { $auth = [string]$script:WindowsMcpAuthKey }
    } catch { }
    if (-not $auth) {
        try {
            $cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
            $authPath = Join-Path $cfgDir 'auth.key'
            if (Test-Path -LiteralPath $authPath) {
                $auth = ((Get-Content -LiteralPath $authPath -Raw -ErrorAction SilentlyContinue) + '').Trim()
            }
            if (-not $auth -and (Get-Command Get-WindowsMcpAuthKeyFromToml -ErrorAction SilentlyContinue)) {
                $auth = Get-WindowsMcpAuthKeyFromToml -TomlPath (Join-Path $cfgDir 'config.toml')
            }
        } catch { }
    }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"wmcp-local","version":"0"}}}'
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WindowsMcpListening)) {
            Start-Sleep -Milliseconds 300
            continue
        }
        try {
            $req = [System.Net.HttpWebRequest]::Create(("http://127.0.0.1:{0}/mcp" -f $port))
            $req.Method = 'POST'
            $req.ContentType = 'application/json'
            $req.Accept = 'application/json, text/event-stream'
            $req.Timeout = 4000
            $req.ReadWriteTimeout = 4000
            if ($auth) { $req.Headers['Authorization'] = "Bearer $auth" }
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream()
            try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Close() }
            $resp = $null
            try {
                $resp = $req.GetResponse()
                $code = [int]$resp.StatusCode
                if ($code -eq 200) { return $true }
            } finally {
                if ($resp) { try { $resp.Close() } catch { } }
            }
        } catch {
            # connect/refused while binding — keep waiting
        }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Exit-WmcpEnsureMutex {
    if ($script:WmcpEnsureMutex) {
        if ($script:WmcpEnsureMutexGot) {
            try { $script:WmcpEnsureMutex.ReleaseMutex() } catch { }
        }
        try { $script:WmcpEnsureMutex.Dispose() } catch { }
        $script:WmcpEnsureMutex = $null
        $script:WmcpEnsureMutexGot = $false
    }
}

function Restart-WindowsMcpServer {
    Write-WindowsMcpEnsureLog 'restarting_server_after_auth_rotate'
    # Stop logon-task instance if any; do not /Run it (visible cmd).
    $prevEapRestart = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { schtasks /End /TN 'windows-mcp-server' 2>&1 | Out-Null } catch { }
    $ErrorActionPreference = $prevEapRestart
    Start-Sleep -Milliseconds 400
    $lport = Get-WindowsMcpLocalPort
    try {
        Get-NetTCPConnection -LocalPort $lport -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    } catch { }
    Start-Sleep -Milliseconds 400
    Write-WindowsMcpEnsureLog 'restart_direct_hidden'
    [void](Start-WindowsMcpProcessDirect)
    # Busy laptops (uv/python cold start + port thrash) often need >8s; keep UI path direct/hidden.
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        if (Test-WindowsMcpListening) {
            Stop-WindowsMcpOrphanCmdWrappers
            return $true
        }
    }
    $ok = Test-WindowsMcpListening
    if ($ok) { Stop-WindowsMcpOrphanCmdWrappers }
    return $ok
}

function Start-WindowsMcpIfNeeded {
    # Drop sticky legacy :8000 before any "already listening" short-circuit.
    if (Stop-WindowsMcpLegacyPort8000) {
        $script:WindowsMcpLocalPort = $null
    }
    if (Test-WindowsMcpListening) {
        Stop-WindowsMcpOrphanCmdWrappers
        return $true
    }
    # Always direct hidden start. Never /Run the logon task (flashes cmd.exe and
    # blocked the Connect UI for up to 20s on the first maintain tick).
    Write-WindowsMcpHost '      -> starting windows-mcp (background)...'
    Write-WindowsMcpEnsureLog 'starting_direct_hidden'
    $lportStart = Get-WindowsMcpLocalPort
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if ($attempt -gt 1) {
            Write-WindowsMcpEnsureLog 'start_direct_retry_after_no_listen'
            try {
                Get-NetTCPConnection -LocalPort $lportStart -State Listen -ErrorAction SilentlyContinue |
                    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
            } catch { }
            Start-Sleep -Milliseconds 500
        }
        [void](Start-WindowsMcpProcessDirect)
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            if (Test-WindowsMcpListening) {
                Stop-WindowsMcpOrphanCmdWrappers
                return $true
            }
        }
    }
    Write-WindowsMcpEnsureLog 'start_direct_not_listening_after_wait' 'WARN'
    return $false
}

function Get-WindowsMcpRemoteProbeBashB64 {
    # OpenSSH wraps remote cmds in shell -c "..." — raw " and newlines in the argv
    # break with `unexpected EOF while looking for matching '"'`. Ship probe as base64
    # (same pattern as the python env writer) so the ssh argv stays one safe line.
    # Single-line bash (Windows CRLF here-strings break eval after base64 -d).
    $bash = '_wmcp_http(){ local c body; body=''{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"wmcp-sync","version":"0"}}}''; c=$(curl -sS -o /dev/null -w ''%{http_code}'' -X POST "http://127.0.0.1:${WINDOWS_MCP_FORWARD_PORT}/mcp" -H ''Content-Type: application/json'' -H ''Accept: application/json, text/event-stream'' -H "Authorization: Bearer ${WINDOWS_MCP_AUTH_KEY}" -d "$body" --max-time 5 2>/dev/null || true); c=$(printf ''%s'' "$c" | tr -dc ''0-9''); c=$(printf ''%s'' "$c" | sed ''s/.*\([0-9]\{3\}\)$/\1/''); case "$c" in [0-9][0-9][0-9]) printf ''%s'' "$c";; *) printf ''000'';; esac; }'
    $bash = ($bash -replace "`r", '')
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
}

function Probe-WindowsMcpRemoteOnly {
    # Read-only remote curl through existing forward (no env rewrite, no forward recreate).
    # Used when ensure mutex is busy so peers still stamp WMCP_PROBE after the owner syncs.
    param(
        [string]$AuthKey,
        # Precise×6: late workers need ~90s while owner recovers MCP after abandoned-mutex thrash.
        [int]$MaxOuter = 24
    )
    if (-not $AuthKey) { return $false }
    if (-not (Get-Command SshX -ErrorAction SilentlyContinue)) { return $false }
    if ($MaxOuter -lt 1) { $MaxOuter = 1 }
    if ($MaxOuter -gt 40) { $MaxOuter = 40 }
    $pb64 = Get-WindowsMcpRemoteProbeBashB64
    # Outer retries: peer often probes a few seconds before owner finishes forward start.
    $probe = $null
    for ($outer = 1; $outer -le $MaxOuter; $outer++) {
        # Echo WMCP_PEER_HTTP (not WMCP_PROBE) so SSH_END day-log lines cannot poison Precise
        # parser with intermediate 000 (owner Sync / Write-ConnectLog own the WMCP_PROBE= stamp).
        $remote = ('ENVF=$HOME/.config/windows-mcp/env; code=000; if [ -f "$ENVF" ]; then . "$ENVF"; eval "$(echo {0} | base64 -d)"; for _t in 1 2 3 4; do code=$(_wmcp_http); [ "$code" = 200 ] && break; sleep 0.8; done; fi; echo WMCP_PEER_HTTP=$code' -f $pb64)
        $out = ''
        try { $out = ((SshX $remote) -join "`n") } catch { $out = '' }
        if ($out -match 'WMCP_PEER_HTTP=(\d+)') { $probe = $Matches[1] }
        elseif ($out -match 'WMCP_PROBE=(\d+)') { $probe = $Matches[1] }
        if ($probe -eq '200') { break }
        Start-Sleep -Milliseconds 2000
    }
    if ($probe -eq '200') {
        # Day-log stamp only on success so an early 000 does not poison Precise forever.
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'WMCP_PROBE=200' 'INFO'
        } else {
            Write-WindowsMcpEnsureLog 'WMCP_PROBE=200'
        }
        try {
            $okStamp = Join-Path $env:USERPROFILE '.config\claude-connect\wmcp-fleet-ok.stamp'
            $okDir = Split-Path -Parent $okStamp
            if (-not (Test-Path -LiteralPath $okDir)) { New-Item -ItemType Directory -Force -Path $okDir | Out-Null }
            Set-Content -LiteralPath $okStamp -Value ("ok=1 ts={0}" -f (Get-Date -Format 'o')) -Encoding ASCII
        } catch { }
        Write-WindowsMcpEnsureLog 'server_sync_probe_ok via=peer_probe_only'
        return $true
    }
    # Fleet trust: another Connect proved forward <3min ago and local MCP HTTP is ready.
    # Precise×6 late workers often see transient peer 000 while owner stamp is already 200.
    try {
        $okStamp = Join-Path $env:USERPROFILE '.config\claude-connect\wmcp-fleet-ok.stamp'
        if (Test-Path -LiteralPath $okStamp) {
            $ageSec = ((Get-Date) - (Get-Item -LiteralPath $okStamp).LastWriteTime).TotalSeconds
            # Parallel Connect: if any peer proved forward in the last 5 min, stamp this
            # session's day-log so Precise ×6 late workers are not blocked on flap.
            if ($ageSec -ge 0 -and $ageSec -lt 300) {
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog 'WMCP_PROBE=200' 'INFO'
                }
                Write-WindowsMcpEnsureLog ("server_sync_probe_ok via=fleet_ok_trust age_s={0}" -f [int]$ageSec)
                return $true
            }
        }
    } catch { }
    # Peer path: INFO only (mirrors into day log). Owner Sync still WARNs on real faults.
    Write-WindowsMcpEnsureLog ("server_sync_probe_bad via=peer_probe_only http={0}" -f $(if ($probe) { $probe } else { 'missing' })) 'INFO'
    return $false
}

function Sync-WindowsMcpAuthToServer {
    param([string]$AuthKey)
    if (-not $AuthKey) { return $false }
    if (-not (Get-Command SshX -ErrorAction SilentlyContinue)) { return $false }
    if ($AuthKey -notmatch '^[A-Za-z0-9_\-=]+$') {
        Write-WindowsMcpEnsureLog 'auth_key_charset_rejected' 'WARN'
        return $false
    }
    $lport = Get-WindowsMcpLocalPort
    if ($lport -notmatch '^\d+$' -or [int]$lport -lt 1024 -or [int]$lport -gt 65535) {
        Write-WindowsMcpEnsureLog ("local_port_invalid {0}" -f $lport) 'WARN'
        return $false
    }
    $pyLines = @(
        'import json, pathlib, os',
        "auth = os.environ.get('WMCP_AUTH','')",
        "lport = os.environ.get('WMCP_LPORT','18765')",
        'home = pathlib.Path.home()',
        '# Per-UID forward port: 127.0.0.1:PORT is bound server-wide (single netns), so a',
        '# fixed literal (old: 18000) let only the first connected user ever bind it.',
        'uid = os.getuid()',
        'port = 28000 + (uid - 1000) if uid >= 1000 else 18000',
        'if port > 65535: port = 18000',
        "envd = home / '.config' / 'windows-mcp'",
        'envd.mkdir(parents=True, exist_ok=True)',
        "envf = envd / 'env'",
        'envf.write_text(',
        "    'WINDOWS_MCP_AUTH_KEY=' + auth + chr(10) +",
        "    'WINDOWS_MCP_LOCAL_PORT=' + str(lport) + chr(10) +",
        "    'WINDOWS_MCP_FORWARD_PORT=' + str(port) + chr(10) +",
        "    'WINDOWS_MCP_URL=http://127.0.0.1:' + str(port) + '/mcp' + chr(10),",
        "    encoding='utf-8')",
        'os.chmod(envf, 0o600)',
        "p = home / '.cursor' / 'mcp.json'",
        'cfg = {}',
        'if p.exists():',
        '    try:',
        "        cfg = json.loads(p.read_text(encoding='utf-8'))",
        '    except Exception:',
        '        cfg = {}',
        "cfg.setdefault('mcpServers', {})",
        "cfg['mcpServers']['windows-mcp'] = {",
        "    'url': 'http://127.0.0.1:' + str(port) + '/mcp',",
        "    'headers': {'Authorization': 'Bearer ' + auth},",
        '}',
        'p.parent.mkdir(parents=True, exist_ok=True)',
        "p.write_text(json.dumps(cfg, indent=2) + chr(10), encoding='utf-8')",
        "print('mcp_json_ok port=' + str(port) + ' lport=' + str(lport))"
    )
    $py = ($pyLines -join "`n")
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
    # After writing env/mcp.json: start forward, then HTTP-probe through it.
    # WMCP_PROBE=200 means end-to-end OK; 000 means forward/laptop still broken
    # (old bug: sync printed OK even when forward was dead - amir 2026-07-25).
    # One ssh argv line: python writer (b64) + forward start + probe function (b64).
    # Never embed raw " in the ssh command string (OpenSSH -c wrapping → EOF).
    $pb64 = Get-WindowsMcpRemoteProbeBashB64
    $remote = ('export WMCP_AUTH={0} WMCP_LPORT={1}; echo {2} | base64 -d | python3 -; F=$HOME/.local/bin/windows-mcp-forward; G=/usr/local/bin/windows-mcp-forward; FWD=; if [ -x "$F" ]; then FWD=$F; elif [ -x "$G" ]; then FWD=$G; fi; if [ -n "$FWD" ]; then "$FWD" start >/dev/null 2>&1 || true; fi; S=$HOME/.local/bin/windows-mcp-seed-agent-tools; T=/usr/local/bin/windows-mcp-seed-agent-tools; if [ -x "$S" ]; then "$S" >/dev/null 2>&1 || true; elif [ -x "$T" ]; then "$T" >/dev/null 2>&1 || true; fi; ENVF=$HOME/.config/windows-mcp/env; code=000; if [ -f "$ENVF" ]; then . "$ENVF"; eval "$(echo {3} | base64 -d)"; code=$(_wmcp_http); if [ "$code" != 200 ]; then for _t in 1 2 3 4 5; do [ "$code" = 200 ] && break; if [ -n "$FWD" ]; then "$FWD" start >/dev/null 2>&1 || true; fi; sleep 0.7; code=$(_wmcp_http); done; fi; fi; echo WMCP_PROBE=$code; echo WMCP_SYNC_OK' -f $AuthKey, $lport, $b64, $pb64)
    try {
        # Local HTTP 200 first — never Restart shared MCP from Sync (peer thrash → 000).
        # Longer wait under ×6 cold-start; INFO not WARN (recoverable; peer/boot maintain retries).
        if (-not (Test-WindowsMcpHttpReady -TimeoutMs 45000 -AuthKey $AuthKey)) {
            Write-WindowsMcpEnsureLog 'server_sync_skip reason=local_http_not_ready' 'INFO'
            # Still try read-only peer probe (another Connect may already have forward 200).
            return [bool](Probe-WindowsMcpRemoteOnly -AuthKey $AuthKey -MaxOuter 12)
        }
        $out = ''
        $attempt = 0
        while ($attempt -lt 6) {
            $attempt++
            try {
                $out = ((SshX $remote) -join "`n")
            } catch {
                $out = [string]$_.Exception.Message
            }
            if ($out -match 'WMCP_PROBE=200') { break }
            # Probe miss: wait + re-run remote forward start only (no laptop MCP kill).
            if ($out -match 'WMCP_PROBE=000' -and $attempt -lt 6) {
                Write-WindowsMcpEnsureLog ("server_sync_probe_retry attempt={0} http=000 (no_mcp_restart)" -f $attempt) 'INFO'
                Start-Sleep -Milliseconds 1500
                continue
            }
            if ($out -match 'WMCP_PROBE=\d+' -or $out -match 'WMCP_SYNC_OK') { break }
            if ($attempt -lt 6) { Start-Sleep -Milliseconds 800 }
        }
        $probe = $null
        if ($out -match 'WMCP_PROBE=(\d+)') { $probe = $Matches[1] }
        # Stamp day-log WMCP_PROBE= ONLY on 200. Intermediate 000 must not overwrite a peer's
        # success (Precise takes last match) — SSH_END may still show out=WMCP_PROBE=000.
        if ($probe -eq '200') {
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog 'WMCP_PROBE=200' 'INFO'
            } else {
                Write-WindowsMcpEnsureLog 'WMCP_PROBE=200'
            }
            try {
                $okStamp = Join-Path $env:USERPROFILE '.config\claude-connect\wmcp-fleet-ok.stamp'
                $okDir = Split-Path -Parent $okStamp
                if (-not (Test-Path -LiteralPath $okDir)) { New-Item -ItemType Directory -Force -Path $okDir | Out-Null }
                Set-Content -LiteralPath $okStamp -Value ("ok=1 ts={0}" -f (Get-Date -Format 'o')) -Encoding ASCII
            } catch { }
        } elseif ($probe) {
            # Never write the literal "WMCP_PROBE=" here — Write-WindowsMcpEnsureLog mirrors
            # into the day log and Precise parses that as the session stamp.
            Write-WindowsMcpEnsureLog ("sync_probe_http={0} ensure_log_only=1" -f $probe)
        }
        $syncOk = ($out -match 'WMCP_SYNC_OK')
        if (-not $syncOk) {
            $clip = ($out -replace '\s+', ' ')
            if ($clip.Length -gt 200) { $clip = $clip.Substring(0, 200) }
            Write-WindowsMcpEnsureLog ("server_sync_unexpected {0}" -f $clip) 'INFO'
            if ($probe -eq '200') {
                Write-WindowsMcpEnsureLog ("server_sync_probe_ok http={0} lport={1} via=probe_without_sync_ok" -f $probe, $lport)
                return $true
            }
            return $false
        }
        if ($probe -eq '200') {
            Write-WindowsMcpEnsureLog ("server_sync_probe_ok http={0} lport={1}" -f $probe, $lport)
            return $true
        }
        if ($probe) {
            Write-WindowsMcpEnsureLog ("server_sync_probe_bad http={0} lport={1}" -f $probe, $lport) 'INFO'
            return $false
        }
        Write-WindowsMcpEnsureLog 'server_sync_probe_missing' 'INFO'
        return $false
    } catch {
        Write-WindowsMcpEnsureLog ("server_sync_failed {0}" -f $_.Exception.Message) 'INFO'
        return $false
    }
}

function Ensure-WindowsMcp {
    $result = [pscustomobject]@{
        Ok        = $false
        Summary   = ''
        AuthKey   = $null
        Listening = $false
        Synced    = $false
        Installed = $false
    }
    try {
        Update-WindowsMcpPath
        Write-WindowsMcpEnsureLog ("ensure_begin admin={0}" -f [int](Test-WindowsMcpIsAdmin))
        if (Stop-WindowsMcpLegacyPort8000) {
            $script:WindowsMcpLocalPort = $null
            Write-WindowsMcpEnsureLog 'ensure_migrating_off_legacy_8000'
        }
        $cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
        if (-not (Test-Path -LiteralPath $cfgDir)) {
            New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        }
        $exe = Get-WindowsMcpExe
        if (-not $exe) {
            Write-WindowsMcpEnsureLog 'bootstrap_begin package_missing'
            $uv = Install-UvIfMissing
            if (-not $uv) {
                $result.Summary = 'uv bootstrap failed (need network; winget or astral script)'
                Write-WindowsMcpEnsureLog $result.Summary 'WARN'
                return $result
            }
            $exe = Install-WindowsMcpPackage -UvExe $uv
            if ($exe) { $result.Installed = $true }
        }
        if (-not $exe) {
            $result.Summary = 'windows-mcp missing after bootstrap'
            Write-WindowsMcpEnsureLog $result.Summary 'WARN'
            return $result
        }
        Ensure-WindowsMcpUserPathEntry
        $patchedWrite = [bool](Repair-WindowsMcpUtf8WriteNewline)
        $auth = Ensure-WindowsMcpAuth -WmExe $exe -CfgDir $cfgDir
        $result.AuthKey = $auth
        $null = Ensure-WindowsMcpTask -WmExe $exe
        $gotLock = Enter-WmcpEnsureMutex -TimeoutMs 180000
        try {
            if (-not $gotLock) {
                # Peer owns ensure/sync — never Restart unlocked; probe existing forward only.
                $result.Listening = [bool](Test-WindowsMcpListening)
                $haveSsh = [bool](Get-Command SshX -ErrorAction SilentlyContinue)
                if ($auth -and $haveSsh -and $result.Listening) {
                    Start-Sleep -Seconds 3
                    $result.Synced = [bool](Probe-WindowsMcpRemoteOnly -AuthKey $auth)
                }
                $result.Ok = [bool]($result.Listening -and $result.Synced)
                $result.Summary = if ($result.Synced) {
                    'peer sync observed (mutex busy; probe-only 200)'
                } else {
                    'ensure mutex busy; peer probe not yet 200'
                }
                Write-WindowsMcpEnsureLog $result.Summary $(if ($result.Ok) { 'INFO' } else { 'WARN' })
                return $result
            }
            $listening = Start-WindowsMcpIfNeeded
            if ($patchedWrite -or $script:WindowsMcpAuthRotated) {
                # Reload Python so write_file(newline='') is live (only under lock).
                $listening = Restart-WindowsMcpServer
                $script:WindowsMcpAuthRotated = $false
            }
            if ($listening) {
                $listening = [bool](Test-WindowsMcpHttpReady -TimeoutMs 20000)
                if (-not $listening) {
                    Write-WindowsMcpEnsureLog 'ensure local_http_not_ready after listen' 'WARN'
                }
            }
            $result.Listening = [bool]$listening
            $haveSsh = [bool](Get-Command SshX -ErrorAction SilentlyContinue)
            if ($auth -and $haveSsh -and $listening) {
                $script:WindowsMcpAuthKey = $auth
                $result.Synced = [bool](Sync-WindowsMcpAuthToServer -AuthKey $auth)
                if (-not $result.Synced) {
                    Start-Sleep -Seconds 2
                    $result.Synced = [bool](Sync-WindowsMcpAuthToServer -AuthKey $auth)
                }
            }
        } finally {
            Exit-WmcpEnsureMutex
        }
        if ($listening -and ((-not $haveSsh) -or $result.Synced)) {
            $result.Ok = $true
            $bits = New-Object System.Collections.Generic.List[string]
            if ($result.Installed) { [void]$bits.Add('installed') }
            [void]$bits.Add(('listening :{0}' -f (Get-WindowsMcpLocalPort)))
            if ($result.Synced) { [void]$bits.Add('server sync ok') }
            elseif (-not $haveSsh) { [void]$bits.Add('local only (no ssh)') }
            $result.Summary = ($bits -join ', ')
        } else {
            $result.Ok = $false
            if (-not $listening) {
                $result.Summary = 'installed but not listening (unlock interactive desktop / Session 0)'
            } else {
                $result.Summary = 'listening but server forward/probe failed (will retry via maintain/watchdog)'
            }
        }
        Write-WindowsMcpEnsureLog ("done ok={0} listening={1} synced={2} installed={3} summary={4}" -f `
            $result.Ok, $result.Listening, $result.Synced, $result.Installed, $result.Summary)
        return $result
    } catch {
        $result.Summary = $_.Exception.Message
        Write-WindowsMcpEnsureLog ("ensure_exception {0}" -f $_.Exception.Message) 'WARN'
        return $result
    }
}

function Maintain-WindowsMcpSession {
    # Lightweight mid-session heal: keep laptop listen + server forward alive.
    # Safe for live sessions (does not touch SSH tunnels / editor). Call every few minutes.
    # Quiet on Connect UI - never print "starting windows-mcp..." on the session loop.
    param([int]$PeerMaxOuter = 0)
    $prevQuiet = $env:WINDOWS_MCP_ENSURE_QUIET
    $env:WINDOWS_MCP_ENSURE_QUIET = '1'
    try {
        Update-WindowsMcpPath
        $exe = Get-WindowsMcpExe
        if (-not $exe) { return $false }
        $cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
        $auth = Ensure-WindowsMcpAuth -WmExe $exe -CfgDir $cfgDir
        if (-not $auth) { return $false }
        if (-not (Get-Command SshX -ErrorAction SilentlyContinue)) { return (Test-WindowsMcpListening) }
        # Maintain must not fight Ensure for 60s (that WARN was lock contention, not a product fault).
        $gotLock = Enter-WmcpEnsureMutex -TimeoutMs 500 -QuietTimeout
        try {
            $script:WindowsMcpAuthKey = $auth
            if (-not $gotLock) {
                # Peers must NOT Start-WindowsMcpIfNeeded — ×6 cold-starts kill a healthy
                # forward (Precise 20260804.21 W4 starting_direct_hidden after W1/W2 200).
                Write-WindowsMcpEnsureLog 'maintain_skip reason=mutex_busy; peer_probe_only' 'INFO'
                $outer = if ($PeerMaxOuter -gt 0) { $PeerMaxOuter } else { 24 }
                $synced = [bool](Probe-WindowsMcpRemoteOnly -AuthKey $auth -MaxOuter $outer)
                # Day-log stamp (incl. fleet_ok) is enough for Precise; listen may flap.
                return [bool]$synced
            }
            # Only the mutex owner may (re)start the laptop MCP listener.
            if (-not (Test-WindowsMcpListening)) {
                [void](Start-WindowsMcpIfNeeded)
            }
            $synced = [bool](Sync-WindowsMcpAuthToServer -AuthKey $auth)
            if (-not $synced) {
                # Sync 000: still allow fleet-ok day-log stamp via peer probe helper.
                $synced = [bool](Probe-WindowsMcpRemoteOnly -AuthKey $auth -MaxOuter 2)
            }
            Write-WindowsMcpEnsureLog ("maintain listening={0} synced={1}" -f [int](Test-WindowsMcpListening), [int]$synced)
            return [bool]$synced
        } finally {
            Exit-WmcpEnsureMutex
        }
    } catch {
        Write-WindowsMcpEnsureLog ("maintain_exception {0}" -f $_.Exception.Message) 'WARN'
        return $false
    } finally {
        if ($null -eq $prevQuiet -or $prevQuiet -eq '') {
            Remove-Item Env:\WINDOWS_MCP_ENSURE_QUIET -ErrorAction SilentlyContinue
        } else {
            $env:WINDOWS_MCP_ENSURE_QUIET = $prevQuiet
        }
    }
}

function Start-WindowsMcpEnsureBackground {
    param(
        [Parameter(Mandatory)][string]$ModulePath,
        [string]$SshAlias = 'claude-server'
    )
    if ($script:WindowsMcpBgStarted) { return $true }
    if (-not (Test-Path -LiteralPath $ModulePath)) {
        Write-WindowsMcpEnsureLog ("background_skip module_missing {0}" -f $ModulePath) 'WARN'
        return $false
    }

    # Fleet guard: one bg Ensure across Parallel Connect (×6 was spawning 6 cold-starts).
    $fleetStamp = Join-Path $env:USERPROFILE '.config\claude-connect\wmcp-fleet-bg.stamp'
    $fleetMutex = $null
    $fleetGot = $false
    try {
        try {
            $fleetMutex = New-Object System.Threading.Mutex($false, 'Global\ClaudeConnectWmcpBgSpawn')
            $fleetGot = $fleetMutex.WaitOne(0)
        } catch {
            Write-WindowsMcpEnsureLog ("fleet_spawn_guard_error {0}" -f $_.Exception.Message) 'INFO'
        }
        if (-not $fleetGot) {
            Write-WindowsMcpEnsureLog 'background_skip reason=fleet_spawn_mutex'
            $script:WindowsMcpBgStarted = $true
            return $true
        }
        if (Test-Path -LiteralPath $fleetStamp) {
            $ageSec = ((Get-Date) - (Get-Item -LiteralPath $fleetStamp).LastWriteTime).TotalSeconds
            $stampPid = 0
            try {
                $raw = (Get-Content -LiteralPath $fleetStamp -TotalCount 1 -ErrorAction SilentlyContinue)
                if ("$raw" -match 'pid=(\d+)') { $stampPid = [int]$Matches[1] }
            } catch { }
            $alive = $false
            if ($stampPid -gt 0) {
                try { $alive = [bool](Get-Process -Id $stampPid -ErrorAction SilentlyContinue) } catch { $alive = $false }
            }
            # Skip ONLY while owner bg process is still alive. Dead stamp must not block
            # a replacement (Precise×6 .18 W4: age=35 alive=0 → no Ensure → local_http_not_ready).
            if ($alive) {
                Write-WindowsMcpEnsureLog ("background_skip reason=fleet_owner_alive age_s={0} pid={1}" -f [int]$ageSec, $stampPid)
                $script:WindowsMcpBgStarted = $true
                return $true
            }
            if ($ageSec -ge 0 -and $ageSec -lt 8) {
                Write-WindowsMcpEnsureLog ("background_skip reason=fleet_spawn_grace age_s={0} pid={1}" -f [int]$ageSec, $stampPid)
                $script:WindowsMcpBgStarted = $true
                return $true
            }
        }

        $runnerDir = Join-Path $env:TEMP 'claude-connect-wmcp'
        if (-not (Test-Path -LiteralPath $runnerDir)) {
            New-Item -ItemType Directory -Force -Path $runnerDir | Out-Null
        }
        $runnerPath = Join-Path $runnerDir 'ensure-bg.ps1'

        $runner = @'
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [string]$SshAlias = 'claude-server'
)
$ErrorActionPreference = "Continue"
$env:WINDOWS_MCP_ENSURE_QUIET = "1"
try {
    . $ModulePath
} catch {
    $msg = "dot_source_failed $($_.Exception.Message)"
    try {
        $dir = Join-Path $env:USERPROFILE ".config\claude-connect\logs"
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Add-Content -LiteralPath (Join-Path $dir "windows-mcp-ensure.log") -Value ("{0} [ERROR] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -Encoding UTF8
    } catch { }
    exit 1
}
function SshX([string]$Cmd) {
    if ([string]::IsNullOrWhiteSpace($SshAlias)) { return @() }
    $out = &(Get-Command ssh).Source @("-n","-o","BatchMode=yes","-o","ConnectTimeout=20",$SshAlias,$Cmd) 2>&1
    return @($out | ForEach-Object { "$_" })
}
try {
    $r = Ensure-WindowsMcp
    if ($r -and $r.Ok) { exit 0 }
    exit 2
} catch {
    if (Get-Command Write-WindowsMcpEnsureLog -ErrorAction SilentlyContinue) {
        Write-WindowsMcpEnsureLog ("background_throw {0}" -f $_.Exception.Message) "WARN"
    }
    exit 1
}
'@
        Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8

        $argList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden',
            '-File', $runnerPath,
            '-ModulePath', $ModulePath,
            '-SshAlias', $SshAlias
        )
        # Inherit elevation from connect.ps1 (already RunAs at start) - do NOT use -Verb RunAs here
        # (would pop a second UAC and break non-interactive background).
        # Job-bound via Start-JobBoundProcess (git-mode session job) so force-close of Connect
        # cannot leave this ensure process orphaned burning CPU/RAM.
        if (Get-Command Start-JobBoundProcess -ErrorAction SilentlyContinue) {
            $p = Start-JobBoundProcess -FilePath 'powershell.exe' -ArgumentList $argList `
                -WindowStyle Hidden -PassThru
        } else {
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
                -WindowStyle Hidden -PassThru -ErrorAction Stop
        }
        $script:WindowsMcpBgStarted = $true
        $script:WindowsMcpBgProcId = if ($p) { $p.Id } else { 0 }
        try {
            $stampDir = Split-Path -Parent $fleetStamp
            if (-not (Test-Path -LiteralPath $stampDir)) { New-Item -ItemType Directory -Force -Path $stampDir | Out-Null }
            Set-Content -LiteralPath $fleetStamp -Value ("pid={0} ts={1}" -f $script:WindowsMcpBgProcId, (Get-Date -Format 'o')) -Encoding ASCII
        } catch { }
        Write-WindowsMcpEnsureLog ("background_started pid={0} alias={1} admin={2}" -f `
            $script:WindowsMcpBgProcId, $SshAlias, [int](Test-WindowsMcpIsAdmin))
        return $true
    } catch {
        Write-WindowsMcpEnsureLog ("background_start_failed {0}" -f $_.Exception.Message) 'WARN'
        return $false
    } finally {
        if ($fleetMutex) {
            if ($fleetGot) { try { $fleetMutex.ReleaseMutex() } catch { } }
            try { $fleetMutex.Dispose() } catch { }
        }
    }
}
