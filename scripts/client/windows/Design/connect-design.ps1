# connect-design.ps1 - Claude Design launcher for Windows.
# Usage: double-click connect-design.bat

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $PSScriptRoot 'connect-design.ps1')`""
    exit
}

$ErrorActionPreference = "Continue"
$ServerIP   = "192.168.210.240"
$RemoteUser = "designer"
$Alias      = "claude-design-server"
$LocalPort  = 6080
$SshDir     = Join-Path $env:USERPROFILE ".ssh"
$LaptopUser = $env:USERNAME

function Die($m)  { Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor DarkYellow }
function Step($m) { Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan }
function StepOk {
    param([string]$d = '')
    if ($d) { Write-Host " $d" -ForegroundColor Green } else { Write-Host " ok" -ForegroundColor Green }
}
function StepFail {
    param([string]$d = '')
    Write-Host " failed" -ForegroundColor Red
    if ($d) { Write-Host "      -> $d" -ForegroundColor DarkGray }
}

function PortOpen([string]$h, [int]$p) {
    try {
        $t = New-Object System.Net.Sockets.TcpClient
        $r = $t.BeginConnect($h, $p, $null, $null)
        $ok = $r.AsyncWaitHandle.WaitOne(1000)
        if ($ok) { try { $t.EndConnect($r) } catch { $ok = $false } }
        $t.Close(); return $ok
    } catch { return $false }
}

function Test-LocalPort([int]$port) {
    try {
        $t = New-Object System.Net.Sockets.TcpClient
        $r = $t.BeginConnect("127.0.0.1", $port, $null, $null)
        $ok = $r.AsyncWaitHandle.WaitOne(500)
        if ($ok) { try { $t.EndConnect($r) } catch { $ok = $false } }
        $t.Close(); return $ok
    } catch { return $false }
}

function SshX([string]$cmd) {
    $r = & ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=10 `
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 $Alias $cmd 2>$null
    return $r
}

function Remove-SshHostBlock([string]$file, [string]$hostAlias) {
    if (-not (Test-Path $file)) { return }
    $lines = Get-Content $file -Encoding UTF8
    $out = @(); $skip = $false
    foreach ($l in $lines) {
        if ($l -match "^\s*Host\s+$([regex]::Escape($hostAlias))\s*$") { $skip = $true; continue }
        if ($skip -and $l -match "^\s*Host\s+") { $skip = $false }
        if (-not $skip) { $out += $l }
    }
    [System.IO.File]::WriteAllLines($file, $out, [System.Text.UTF8Encoding]::new($false))
}

function Repair-SshPerm([string]$path) {
    if (-not (Test-Path $path)) { return }
    icacls $path /inheritance:r 2>$null | Out-Null
    icacls $path /grant:r "${LaptopUser}:F" 2>$null | Out-Null
}

function KillTunnels {
    try {
        Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match "-L\s+${LocalPort}:" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {
        # Fallback if CIM unavailable
        Get-Process ssh -ErrorAction SilentlyContinue |
            Where-Object { $_.MainModule -and $true } |
            ForEach-Object {
                try {
                    $wmi = Get-WmiObject Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue
                    if ($wmi -and $wmi.CommandLine -match "-L\s+${LocalPort}:") {
                        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
    }
}

function SafeReadKey {
    try {
        if ([Console]::KeyAvailable) {
            return [Console]::ReadKey($true)
        }
    } catch {}
    return $null
}

function FlushKeys {
    try {
        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
    } catch {}
}

# Get screen dimensions before potential elevation issues
Add-Type -AssemblyName System.Windows.Forms
$bounds  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$screenW = if ($bounds.Width  -gt 0) { $bounds.Width  } else { 1920 }
$screenH = if ($bounds.Height -gt 0) { $bounds.Height } else { 1080 }

Clear-Host
Write-Host ""
Write-Host "    Claude Design" -ForegroundColor White
Write-Host "    $ServerIP" -ForegroundColor DarkGray
Write-Host ""

# --- SSH key ---
Step "SSH key"
$KeyFile = Join-Path $SshDir "id_ed25519"
if (-not (Test-Path $SshDir)) { New-Item -ItemType Directory -Force -Path $SshDir | Out-Null }
if (-not (Test-Path $KeyFile)) { & ssh-keygen -t ed25519 -N "" -f $KeyFile -q }
if (Test-Path $KeyFile) {
    Repair-SshPerm $KeyFile
    StepOk
} else {
    StepFail "could not create key"
    Read-Host "    Press Enter to close" | Out-Null; exit 1
}

# --- SSH config ---
$SshCfg = Join-Path $SshDir "config"
if (-not (Test-Path $SshCfg)) { New-Item -ItemType File -Path $SshCfg -Force | Out-Null }
Remove-SshHostBlock $SshCfg $Alias
$cfgBlock = @"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@
[System.IO.File]::AppendAllText($SshCfg, $cfgBlock, [System.Text.UTF8Encoding]::new($false))
Repair-SshPerm $SshCfg

# --- connect ---
$connected = $false
$needsKey  = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan

    # Check for changed host key
    $sshTestOut = & ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=5 $Alias "true" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " $RemoteUser@$ServerIP" -ForegroundColor Green
        $connected = $true; break
    }
    if ($sshTestOut -match 'REMOTE HOST IDENTIFICATION HAS CHANGED' -or $sshTestOut -match 'WARNING: REMOTE HOST') {
        Write-Host " host key changed" -ForegroundColor Yellow
        Warn "Server host key changed - removing old key and retrying..."
        & ssh-keygen -R $ServerIP 2>$null | Out-Null
        & ssh-keygen -R $Alias 2>$null | Out-Null
        # retry immediately
        continue
    }
    if (PortOpen $ServerIP 22) {
        Write-Host " auth failed - installing key now" -ForegroundColor DarkYellow
        $needsKey = $true; break
    }
    Write-Host " no response" -ForegroundColor DarkGray
    if ($attempt -lt 10) { Write-Host "    Waiting 5s..."; Start-Sleep 5 }
}

if (-not $connected -and -not $needsKey) {
    Die "Cannot reach $ServerIP. VPN connected? Server up?"
}

if ($needsKey) {
    Write-Host ""
    Write-Host "    Enter server admin password (one time only):" -ForegroundColor Yellow
    Get-Content "$KeyFile.pub" | & ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    Step "Verifying"
    & ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=6 $Alias "true" 2>$null
    if ($LASTEXITCODE -ne 0) {
        StepFail
        Die "Still cannot connect. Ask admin to add your SSH key to the designer user."
    }
    StepOk "$RemoteUser@$ServerIP"
}

# --- start session on server ---
Step "Starting Chrome session"
$sessionOut = (SshX "designer-start start $screenW $screenH 2>&1") -join "`n"
if ($sessionOut -notmatch 'OK') {
    StepFail $sessionOut.Trim()
    Die "Could not start Chrome session. Ask admin to run setup-designer.sh."
}
$novncPort = ($sessionOut -split "`n" |
    Where-Object { $_ -match '^NOVNC_PORT=' } |
    Select-Object -First 1) -replace '^NOVNC_PORT=',''
if (-not $novncPort -or $novncPort -notmatch '^\d+$') { Die "Could not read noVNC port from server." }

$kickedPrevious = $sessionOut -match 'KICKED_PREVIOUS'
StepOk "port $novncPort"

if ($kickedPrevious) {
    Write-Host ""
    Write-Host "    ** Previous user was disconnected **" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "    Ready" -ForegroundColor Green
Write-Host ""

# --- session loop ---
$browserOpened = $false
$bgTunnel      = $null

# Register cleanup for unexpected exits
$cleanupScript = {
    if ($bgTunnel -and -not $bgTunnel.HasExited) {
        Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
    }
}
Register-EngineEvent PowerShell.Exiting -Action $cleanupScript | Out-Null

$keepRunning = $true
try {
    while ($keepRunning) {
        # Kill any existing tunnel processes
        if ($bgTunnel -and -not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
        }
        KillTunnels

        # Verify port is free
        if (Test-LocalPort $LocalPort) {
            Warn "Port $LocalPort still in use after cleanup."
            $portConn = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
            if ($portConn) {
                $ownerPid = ($portConn | Select-Object -First 1).OwningProcess
                $ownerName = (Get-Process -Id $ownerPid -ErrorAction SilentlyContinue).Name
                Warn "Port held by '$ownerName' (PID $ownerPid)."
            }
            Start-Sleep -Seconds 2
        }

        Step "SSH tunnel"
        $sshArgs = @(
            '-N',
            '-o', 'ExitOnForwardFailure=yes',
            '-o', 'ServerAliveInterval=10',
            '-o', 'ServerAliveCountMax=3',
            '-L', "${LocalPort}:127.0.0.1:${novncPort}",
            $Alias
        )
        $bgTunnel = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList $sshArgs
        StepOk "pid $($bgTunnel.Id)"

        $up = $false
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 2
            Write-Host -NoNewline "    Tunnel check $i/15..." -ForegroundColor DarkGray
            if ($bgTunnel.HasExited) {
                Write-Host " SSH process died" -ForegroundColor Red; break
            }
            if (Test-LocalPort $LocalPort) {
                Write-Host " port $LocalPort is open" -ForegroundColor Green
                $up = $true; break
            }
            Write-Host " not ready yet" -ForegroundColor DarkGray
        }

        if (-not $up) {
            Warn "Tunnel did not come up on port $LocalPort"
            Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
            $rk = ''
            while ($rk -ne 'r' -and $rk -ne 'q') {
                $ki2 = SafeReadKey
                if ($ki2) {
                    $kc2 = $ki2.KeyChar.ToString().ToLower()
                    if ($kc2 -eq 'r' -or $ki2.Key -eq [ConsoleKey]::R) { $rk = 'r' }
                    elseif ($kc2 -eq 'q' -or $ki2.Key -eq [ConsoleKey]::Q) { $rk = 'q' }
                } else { Start-Sleep -Milliseconds 200 }
            }
            if ($rk -ne 'r') { $keepRunning = $false }
            continue
        }

        if (-not $browserOpened) {
            $browserOpened = $true
            Step "Opening Claude Design"
            $amp    = [char]38
            $url    = "http://localhost:${LocalPort}/vnc.html?autoconnect=true${amp}resize=none${amp}quality=9${amp}compression=0${amp}reconnect=true${amp}reconnect_delay=2000${amp}view_only=0"
            $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
            $edge   = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
            if (Test-Path $chrome) {
                Start-Process $chrome -ArgumentList @("--app=$url", '--start-fullscreen', '--disable-infobars')
            } elseif (Test-Path $edge) {
                Start-Process $edge -ArgumentList @("--app=$url", '--start-fullscreen', '--disable-infobars')
            } else {
                Start-Process $url
            }
            StepOk $url
        }

        Write-Host ""
        Write-Host "    ============================================" -ForegroundColor DarkGray
        Write-Host "    Claude Design is open" -ForegroundColor Cyan
        Write-Host "    Keep this window open while you work" -ForegroundColor DarkGray
        Write-Host "    R = reconnect   Q or Enter = disconnect" -ForegroundColor DarkGray
        Write-Host "    ============================================" -ForegroundColor DarkGray
        Write-Host ""

        FlushKeys

        $action = 'q'
        $gotKey = $false
        while (-not $bgTunnel.HasExited) {
            $ki = SafeReadKey
            if ($ki) {
                $kc = $ki.KeyChar.ToString().ToLower()
                if ($kc -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) {
                    $action = 'r'; $gotKey = $true; break
                } elseif ($kc -eq 'q' -or $ki.Key -eq [ConsoleKey]::Q -or $ki.Key -eq [ConsoleKey]::Enter) {
                    $action = 'q'; $gotKey = $true; break
                }
                # any other key: ignore, keep waiting
            }
            Start-Sleep -Milliseconds 500
        }

        # Tunnel died on its own — always check kick regardless of whether a key was pressed
        if ($bgTunnel.HasExited -and -not ($gotKey -and $action -eq 'q')) {
            $kickCheck = (SshX "designer-start check-kicked 2>&1") -join ""
            if ($kickCheck -match 'KICKED') {
                Write-Host ""
                Write-Host "    ** You were disconnected by another designer **" -ForegroundColor Red
                Write-Host "    Connection taken by another designer." -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "    R = take back   Q = exit" -ForegroundColor DarkGray
                $rk = ''
                while ($rk -ne 'r' -and $rk -ne 'q') {
                    $ki3 = SafeReadKey
                    if ($ki3) {
                        $kc3 = $ki3.KeyChar.ToString().ToLower()
                        if ($kc3 -eq 'r' -or $ki3.Key -eq [ConsoleKey]::R) { $rk = 'r' }
                        elseif ($kc3 -eq 'q' -or $ki3.Key -eq [ConsoleKey]::Q) { $rk = 'q' }
                    } else { Start-Sleep -Milliseconds 200 }
                }
                if ($rk -eq 'q') { $keepRunning = $false; $action = 'q' }
                else { $action = 'r' }
                # noVNC inside the existing browser auto-reconnects — do NOT open a new window
            } elseif (-not $gotKey) {
                # Unexpected drop (not kicked, no key pressed) — auto-reconnect silently
                Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
                $action = 'r'
                # noVNC auto-reconnects — do NOT open a new browser window
            }
        }

        if ($bgTunnel -and -not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
        }

        if ($action -ne 'r') { $keepRunning = $false; continue }
        # $browserOpened is never reset — Chrome opens once and stays open.
        # noVNC inside it auto-reconnects on every tunnel re-establishment.

        Write-Host ""
        # Add small jitter to reduce simultaneous reconnect collisions
        $jitter = Get-Random -Minimum 1 -Maximum 4
        $waitSec = 2 + $jitter
        Write-Host "    Reconnecting in ${waitSec}s..." -ForegroundColor Cyan
        Start-Sleep -Seconds $waitSec
        Write-Host ""

        $sessionOut = (SshX "designer-start start $screenW $screenH 2>&1") -join "`n"
        if ($sessionOut -match 'KICKED_PREVIOUS') {
            Write-Host "    ** Previous user was disconnected **" -ForegroundColor Yellow
        }
        if ($sessionOut -match 'OK') {
            $np = ($sessionOut -split "`n" |
                Where-Object { $_ -match '^NOVNC_PORT=' } |
                Select-Object -First 1) -replace '^NOVNC_PORT=',''
            if ($np) {
                $novncPort = $np
            } else {
                Warn "Reconnect succeeded but no port returned; reusing port $novncPort"
            }
        } else {
            Warn "Server did not confirm session start. Retrying..."
            Start-Sleep -Seconds 3
            continue
        }
    }
} finally {
    if ($bgTunnel -and -not $bgTunnel.HasExited) {
        Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
    }
    KillTunnels
}

Write-Host ""
Write-Host "    Disconnected. Chrome session stays alive on server." -ForegroundColor DarkGray
Write-Host ""

