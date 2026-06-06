# connect.ps1 - Claude Code launcher for Windows.
# Usage:  double-click connect.bat
#         connect.bat -Setup   (reconfigure username)

param([switch]$Setup)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $PSCommandPath -replace "'", "''"
    $setupFlag  = if ($Setup) { ' -Setup' } else { '' }
    $cmd = "& '$scriptPath'$setupFlag; if (`$LASTEXITCODE -ne 0) { Write-Host ''; Read-Host '    Press Enter to close' }"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd
    exit
}

$ErrorActionPreference = "Continue"
$ServerIP = "192.168.210.240"
$Alias    = "claude-server"
$CfgDir   = Join-Path $env:USERPROFILE ".config\claude-connect"
$Cfg      = Join-Path $CfgDir "connect.conf"
$SshDir   = Join-Path $env:USERPROFILE ".ssh"
$CM       = '$HOME/.local/bin/claude-mount'

function Die($m)   { Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
function Warn($m)  { Write-Host "  [!] $m" -ForegroundColor DarkYellow }
function Step($m)  { Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan }
function StepOk  {
    param([string]$d='')
    if ($d) { Write-Host " $d" -ForegroundColor Green } else { Write-Host " ok" -ForegroundColor Green }
    foreach ($fx in $script:pendingFixes) { Write-Host "      -> fixed: $fx" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
}
function StepFail {
    param([string]$d='')
    Write-Host " failed" -ForegroundColor Red
    if ($d) { Write-Host "      -> $d" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
}
$script:pendingFixes = @()

function Repair-SshPerm([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { return }
    $out = (icacls $path 2>$null) -join ' '
    icacls $path /reset 2>$null | Out-Null
    icacls $path /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null
    if ($out -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "$label permissions" }
}

function Install-ServerKey([string]$pub, [bool]$ForceRestart = $false) {
    $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    $userFile  = Join-Path $SshDir "authorized_keys"

    # Fix permissions on adminFile FIRST so we can write to it
    $adminDir = Split-Path $adminFile
    if (Test-Path $adminDir) {
        if (-not (Test-Path $adminFile)) { New-Item -ItemType File -Path $adminFile -Force | Out-Null }
        $_adminOut = (icacls $adminFile 2>$null) -join ' '
        icacls $adminFile /reset 2>$null | Out-Null
        icacls $adminFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null | Out-Null
        if ($_adminOut -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "administrators_authorized_keys permissions" }
    }

    # Now write the key to both files and fix their permissions
    foreach ($akFile in @($adminFile, $userFile)) {
        if (-not (Test-Path (Split-Path $akFile))) { continue }
        if (-not (Test-Path $akFile)) { New-Item -ItemType File -Path $akFile -Force -ErrorAction SilentlyContinue | Out-Null }
        if (-not (Test-Path $akFile)) { continue }
        $lines = @(Get-Content $akFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
        if ($lines -notcontains $pub) { Add-Content -Path $akFile -Value $pub -Encoding ASCII }
        if ($akFile -eq $userFile) { Repair-SshPerm $akFile "authorized_keys" }
    }

    # Always restart sshd when forced (e.g. after key rejection).
    # administrators_authorized_keys requires a restart on some Windows configurations.
    # On normal first-time setup, only start if stopped (no unnecessary restart).
    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($ForceRestart -and $sshdSvc -and $sshdSvc.Status -eq 'Running') {
        Restart-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
        if (-not $sshdSvc -or $sshdSvc.Status -ne 'Running') {
            $script:pendingFixes += "sshd restart failed - run connect.bat as administrator"
        }
    } elseif (-not $sshdSvc -or $sshdSvc.Status -ne 'Running') {
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function SshX([string]$Cmd) {
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 $Alias $Cmd
}

function Test-Tunnel {
    # Short timeout so VPN loss is detected quickly (3s connect + 2s port check)
    $r = ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=3 `
             -o ServerAliveInterval=2 -o ServerAliveCountMax=2 `
             $Alias "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port' 2>/dev/null && echo UP" 2>$null
    return ($r -match 'UP')
}

function PortOpen($ip, $port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ok  = $tcp.BeginConnect($ip, $port, $null, $null).AsyncWaitHandle.WaitOne(3000)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Remove-SshHostBlock($cfgPath, $alias) {
    if (-not (Test-Path $cfgPath)) { return }
    $out  = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($ln in (Get-Content $cfgPath)) {
        if ($ln -match '^\s*Host\s+(.+)$') { $skip = (($matches[1].Trim() -split '\s+') -contains $alias) }
        if (-not $skip) { $out.Add($ln) }
    }
    Set-Content -Path $cfgPath -Value $out -Encoding ASCII
}

function Get-Mounts {
    # Use 'list' (reads configs only, fast) instead of 'status' (checks mounts, slow/hangs on stale mounts)
    $out = @()
    foreach ($line in ((SshX "$CM list 2>/dev/null") -split "`n")) {
        if ($line.Trim() -match '^([^\|]+)\|([^\|]*)\|([^\|]*)\|([^\|]+)$') {
            $out += [PSCustomObject]@{
                Id    = $matches[1].Trim()
                Label = $matches[2].Trim()
                Path  = $matches[4].Trim()
                On    = $false
            }
        }
    }
    return $out
}

function Show-Mounts($mounts) {
    Write-Host "    Projects" -ForegroundColor White
    Write-Host ""
    $i = 1
    foreach ($m in $mounts) {
        if ($m.On) {
            Write-Host -NoNewline ("    {0}  {1}" -f $i, $m.Label) -ForegroundColor White
            Write-Host "  (on)" -ForegroundColor Green
        } else {
            Write-Host ("    {0}  {1}" -f $i, $m.Label) -ForegroundColor DarkGray
        }
        $i++
    }
    Write-Host ""
    Write-Host "    a add   e edit   d delete   c config   q quit" -ForegroundColor DarkGray
    Write-Host ""
}

function Select-Mount($mounts, $n) {
    if ($n -match '^\d+$') {
        $i = [int]$n - 1
        if ($i -ge 0 -and $i -lt $mounts.Count) { return $mounts[$i] }
    }
    return $null
}

function Add-Project {
    Write-Host ""
    Write-Host "    Add project" -ForegroundColor White
    Write-Host ""
    $nPath = (Read-Host "    Folder on your laptop (e.g. D:\Smart)").Trim() -replace '\\','/'
    if (-not $nPath) { Warn "Path is required."; return $null }
    if ($nPath -match '^[A-Za-z]:$') { $nPath = "$nPath/" }
    $idSrc = $nPath -replace '/+$',''
    $nId   = (($idSrc -split '/')[-1]).ToLower() -replace '[^a-z0-9_-]','-' -replace '-+','-' -replace '^-|-$',''
    $nLbl  = if ($nId) { (Get-Culture).TextInfo.ToTitleCase(($nId -replace '-',' ')) } else { "" }
    $d = (Read-Host "    Name [$nLbl]").Trim(); if ($d) { $nLbl = $d }
    if (-not $nId) { $nId = $nLbl.ToLower() -replace '[^a-z0-9_-]','-' -replace '-+','-' -replace '^-|-$','' }
    if (-not $nId) { Warn "Could not derive a project name."; return $null }
    $nLpath = "/home/$RemoteUser/mounts/$nId"
    Write-Host ""
    $out = SshX "$CM add '$nId' '$nLbl' '$nPath' '$nLpath'" 2>&1
    if ($LASTEXITCODE -ne 0) { Warn $out; return $null }
    return [PSCustomObject]@{ Id = $nId; Path = $nLpath }
}

New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
New-Item -ItemType Directory -Force -Path $SshDir  | Out-Null

# Fix .ssh dir permissions early (silently, before header clears screen)
$_dirOut = (icacls $SshDir 2>$null) -join ' '
$_dirFixed = $_dirOut -match '\(I\)|Everyone|BUILTIN\\Users'
icacls $SshDir /reset 2>$null | Out-Null
icacls $SshDir /inheritance:r /grant "$env:USERNAME`:(OI)(CI)F" 2>$null | Out-Null

# header
Clear-Host
Write-Host ""
Write-Host "    Claude Code" -ForegroundColor White
Write-Host "    $Alias  |  $ServerIP" -ForegroundColor DarkGray
Write-Host ""
if ($_dirFixed) { Write-Host "      -> fixed: .ssh directory permissions" -ForegroundColor DarkGray; Write-Host "" }

# config
if ($Setup -or -not (Test-Path $Cfg)) {
    Write-Host "  First-time setup" -ForegroundColor Cyan
    Write-Host ""
    $RemoteUser = Read-Host "    Server username"
    @("REMOTE_USER=$RemoteUser", "LAPTOP_USER=$env:USERNAME") | Set-Content -Path $Cfg -Encoding ASCII
    Write-Host ""
}
$conf = @{}
Get-Content $Cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$'){ $conf[$matches[1]] = $matches[2] } }
$RemoteUser = $conf["REMOTE_USER"]
$LaptopUser = $conf["LAPTOP_USER"]

# SSH key
Step "Laptop SSH key"
$keyA = Join-Path $SshDir "id_ed25519"
if (-not (Test-Path $keyA)) { ssh-keygen -t ed25519 -N '""' -f $keyA -q }
if (Test-Path $keyA) {
    Repair-SshPerm $keyA "SSH private key"
    StepOk
} else { StepFail "could not create key"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }

# SSH config
$sshCfg = Join-Path $SshDir "config"
if (-not (Test-Path $sshCfg)) { New-Item -ItemType File -Path $sshCfg | Out-Null }
Remove-SshHostBlock $sshCfg $Alias
@"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@ | Add-Content -Path $sshCfg -Encoding ASCII
# Fix SSH config permissions silently - shown later under the step that calls StepOk
icacls $sshCfg /reset 2>$null | Out-Null
icacls $sshCfg /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null

# connect - retry until reachable, 5s between attempts
$connected = $false
$needsKey  = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=5 $Alias "true" 2>$null
    $sw.Stop()
    $connT = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Host " $RemoteUser@$ServerIP" -ForegroundColor Green
        $connected = $true; break
    }
    if (PortOpen $ServerIP 22) {
        Write-Host " auth failed (${connT}s) - no key, installing now" -ForegroundColor DarkYellow
        $needsKey = $true; break
    }
    Write-Host " no response (${connT}s)" -ForegroundColor DarkGray
    if ($attempt -lt 10) {
        Write-Host "    Waiting 5s (VPN on? Server up?)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

if (-not $connected -and -not $needsKey) {
    Write-Host ""
    Warn "Cannot reach $ServerIP after 10 attempts"
    Warn "VPN connected? Server running?"
    Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}

if ($needsKey) {
    Write-Host ""
    Write-Host "    Enter server password (one time only):" -ForegroundColor Yellow
    Get-Content "$keyA.pub" | ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $keyCopyOk = ($LASTEXITCODE -eq 0)
    Step "Verifying connection"
    $verifySW = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=6 $Alias "true" 2>$null
    $verifySW.Stop()
    $verifyT = [math]::Round($verifySW.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -ne 0) {
        if (-not $keyCopyOk) { StepFail "key copy failed after ${verifyT}s - wrong password?" }
        else { StepFail "still cannot connect after ${verifyT}s" }
        Write-Host ""
        Warn "Cannot connect - user=$RemoteUser  host=$ServerIP"
        Write-Host ""
        Write-Host "    Current username: $RemoteUser" -ForegroundColor DarkGray
        $fix = (Read-Host "    Username changed? Enter new username (or Enter to exit)").Trim()
        if ($fix) {
            @("REMOTE_USER=$fix", "LAPTOP_USER=$env:USERNAME") | Set-Content -Path $Cfg -Encoding ASCII
            Remove-SshHostBlock $sshCfg $Alias
            Write-Host ""; Write-Host "    Saved. Re-run connect.bat." -ForegroundColor Green
        }
        Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
    }
    StepOk "$RemoteUser@$ServerIP"
}

# tunnel setup
Step "Getting tunnel port"
$uidStr = (SshX "id -u") -join ""
$Port   = 20000 + [int]($uidStr -replace '\D','')
if ($Port -le 20000) { StepFail "could not get UID from server"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
StepOk "port $Port"

Step "Setting up server key"
SshX "test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q" 2>$null | Out-Null
$PubB = (SshX "cat ~/.ssh/claude_laptop.pub").Trim()
if (-not $PubB) { StepFail "could not read server key"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
Install-ServerKey $PubB
StepOk

Step "Configuring server"
Remove-SshHostBlock $sshCfg $Alias
@"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    RemoteForward $Port localhost:22
    ExitOnForwardFailure no
"@ | Add-Content -Path $sshCfg -Encoding ASCII
Repair-SshPerm $sshCfg "SSH config"
SshX "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\n' '$LaptopUser' '$Port' > ~/.claude-connect.conf" 2>$null | Out-Null
StepOk "laptop=$LaptopUser port=$Port"

# push server scripts (claude-mount + claude-git-setup) if available
$serverScriptDir = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..\server"))
SshX "mkdir -p ~/.local/bin" 2>$null | Out-Null

$src = Join-Path $serverScriptDir "claude-mount.sh"
if (Test-Path $src) {
    scp -o BatchMode=yes -o ConnectTimeout=10 -q $src "${Alias}:~/.local/bin/claude-mount" 2>$null
    SshX "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc" 2>$null | Out-Null
}

$gitSrc = Join-Path $serverScriptDir "claude-git-setup.sh"
if (Test-Path $gitSrc) {
    scp -o BatchMode=yes -o ConnectTimeout=10 -q $gitSrc "${Alias}:~/.local/bin/claude-git-setup" 2>$null
    SshX "chmod +x ~/.local/bin/claude-git-setup" 2>$null | Out-Null
}

Write-Host ""
Write-Host "    Ready" -ForegroundColor Green
Write-Host ""

# mount helpers
Step "Loading projects"
$mounts = @(Get-Mounts)
StepOk "$($mounts.Count) project(s)"
$go = $null

while (-not $go) {
    if ($mounts.Count -eq 0) {
        $go = Add-Project
        if (-not $go) { Die "Could not add project." }
        break
    }

    Show-Mounts $mounts
    $c = (Read-Host "    >").Trim().ToLower()
    Write-Host ""

    if ($c -match '^\d+$') {
        $m = Select-Mount $mounts $c
        if (-not $m) { Warn "Not found."; continue }
        $go = [PSCustomObject]@{ Id = $m.Id; Path = $m.Path }
    } else { switch ($c) {
        "a" {
            $r = Add-Project
            if ($r) { $go = $r } else { $mounts = @(Get-Mounts) }
        }
        "e" {
            $cur = Select-Mount $mounts (Read-Host "    Edit number").Trim()
            if (-not $cur) { Warn "Not found."; continue }
            $curR = ((SshX "grep '^rpath' ~/.claude-mounts.d/$($cur.Id).conf" 2>$null) -replace 'rpath=|"|\r','').Trim()
            Write-Host ""
            $nLbl = (Read-Host "    Name  [$($cur.Label)]").Trim(); if (-not $nLbl) { $nLbl = $cur.Label }
            $nR   = (Read-Host "    Path  [$curR]").Trim() -replace '\\','/'; if (-not $nR) { $nR = $curR }
            $nL   = (Read-Host "    Local [$($cur.Path)]").Trim(); if (-not $nL) { $nL = $cur.Path }
            $editOut = (SshX "$CM edit '$($cur.Id)' '$nLbl' '$nR' '$nL'" 2>&1) | Out-String
            if ($LASTEXITCODE -ne 0) { Warn $editOut.Trim() }
            $mounts = @(Get-Mounts)
        }
        "d" {
            $m = Select-Mount $mounts (Read-Host "    Delete number").Trim()
            if (-not $m) { Warn "Not found."; continue }
            if ((Read-Host "    Delete '$($m.Label)'? [y/N]").Trim().ToLower() -eq "y") {
                $rmOut = (SshX "$CM rm '$($m.Id)'" 2>&1) | Out-String
                if ($LASTEXITCODE -ne 0) { Warn $rmOut.Trim() }
                $mounts = @(Get-Mounts)
            }
        }
        "c" {
            Write-Host ""
            Write-Host "    Configuration" -ForegroundColor White
            Write-Host ""
            Write-Host "    Current username : $RemoteUser" -ForegroundColor DarkGray
            $nUser = (Read-Host "    New server username (Enter to cancel)").Trim()
            if ($nUser -and $nUser -ne $RemoteUser) {
                @("REMOTE_USER=$nUser", "LAPTOP_USER=$env:USERNAME") | Set-Content -Path $Cfg -Encoding ASCII
                Remove-SshHostBlock $sshCfg $Alias
                Write-Host ""; Write-Host "    Saved. Re-run connect.bat." -ForegroundColor Green
                Write-Host ""; exit 0
            } else {
                Write-Host "    Cancelled." -ForegroundColor DarkGray
                Write-Host ""
            }
        }
        "q" { Write-Host ""; exit 0 }
        default { Warn "Enter a number or a/e/d/c/q." }
    }}
}

# mount first, then open VSCode
if ($go) {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Warn "VSCode not found. Install it + the Remote-SSH extension, then re-run."
        Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
    }

    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${Port}:localhost:22" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Step "Checking SSH service"
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') {
        StepFail "OpenSSH Server not running"
        Write-Host ""
        Write-Host "    Trying to start sshd..." -ForegroundColor Yellow
        try {
            Start-Service sshd -ErrorAction Stop
            Start-Sleep -Seconds 1
            $svc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                Write-Host "    sshd started ok." -ForegroundColor Green
            } else {
                Write-Host "    Could not start sshd. Run as admin: Start-Service sshd" -ForegroundColor Red
                Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
            }
        } catch {
            Write-Host "    Error starting sshd: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "    Run as admin: Start-Service sshd" -ForegroundColor DarkGray
            Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
        }
    } else {
        StepOk
    }
    # Ensure Windows Firewall allows inbound SSH (port 22)
    $fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $fwRule) {
        Write-Host "    [!] Firewall rule for SSH missing - adding..." -ForegroundColor Yellow
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
            -ErrorAction SilentlyContinue | Out-Null
    }

    $alreadyDown = $false
    $bgTunnel    = $null

    try {
        :sessionLoop while ($true) {
            # Kill any stale tunnel before starting a new one
            if ($bgTunnel -and -not $bgTunnel.HasExited) {
                Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
            }

            Step "Starting SSH tunnel"
            $bgTunnel = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList @(
                "-N", "-o", "ExitOnForwardFailure=no",
                "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
                "-R", "$Port`:localhost:22", $Alias)
            StepOk "pid $($bgTunnel.Id)"

            $up = $false
            $tunnelMsg = ""
            for ($i = 1; $i -le 8; $i++) {
                Start-Sleep -Seconds 2
                Write-Host -NoNewline "    Tunnel check $i/8..." -ForegroundColor DarkGray
                if ($bgTunnel.HasExited) {
                    $tunnelMsg = "SSH process exited with code $($bgTunnel.ExitCode)"
                    Write-Host " SSH process died" -ForegroundColor Red
                    break
                }
                if (Test-Tunnel) {
                    Write-Host " port $Port is open" -ForegroundColor Green
                    $up = $true; break
                }
                Write-Host " port $Port not open yet" -ForegroundColor DarkGray
            }

            if (-not $up) {
                Write-Host ""
                Warn "Tunnel did not come up on port $Port"
                if ($tunnelMsg) {
                    Warn $tunnelMsg
                } elseif (-not (PortOpen $ServerIP 22)) {
                    Warn "Server unreachable - VPN disconnected?"
                } else {
                    Warn "Check Windows Firewall - port 22 must allow inbound connections"
                }
                Write-Host ""
                Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
                $rk = ''
                while ($rk -ne 'r' -and $rk -ne 'q') {
                    if ([Console]::KeyAvailable) { $rk = ([Console]::ReadKey($true)).KeyChar.ToString().ToLower() }
                    else { Start-Sleep -Milliseconds 200 }
                }
                if ($rk -eq 'r') { Write-Host ""; continue }
                $alreadyDown = $true; break sessionLoop
            }

            SshX "$CM recover" 2>$null | Out-Null

            Step "Mounting files"
            $mountSW = [System.Diagnostics.Stopwatch]::StartNew()
            $mountOut = (SshX "$CM up '$($go.Id)' 2>&1") | Out-String
            $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
            $mountOk  = $LASTEXITCODE -eq 0 -and $mountOut -notmatch 'error:|FAILED|No tunnel|not configured'

            if (-not $mountOk -and $mountOut -match 'key auth failed|connection reset|reset by peer|publickey|Permission denied') {
                Write-Host " retrying..." -ForegroundColor DarkGray
                Warn "Key rejected - reinstalling server key and restarting sshd"
                $newPub = (SshX "cat ~/.ssh/claude_laptop.pub").Trim()
                if ($newPub) {
                    Install-ServerKey $newPub -ForceRestart $true
                    Step "Mounting files"
                    $mountSW = [System.Diagnostics.Stopwatch]::StartNew()
                    $mountOut = (SshX "$CM up '$($go.Id)' 2>&1") | Out-String
                    $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
                    $mountOk  = $LASTEXITCODE -eq 0 -and $mountOut -notmatch 'error:|FAILED|No tunnel|not configured'
                }
            }

            if (-not $mountOk) {
                StepFail $mountOut.Trim()
                if ($mountOut -match 'No such file|not found|cannot find') {
                    Warn "Path not found on laptop. Use 'e edit' to correct the project path."
                }
                Write-Host ""
                Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
                $rk = ''
                while ($rk -ne 'r' -and $rk -ne 'q') {
                    if ([Console]::KeyAvailable) { $rk = ([Console]::ReadKey($true)).KeyChar.ToString().ToLower() }
                    else { Start-Sleep -Milliseconds 200 }
                }
                if ($rk -eq 'r') { Write-Host ""; continue }
                $alreadyDown = $true; break sessionLoop
            }

            StepOk "${mountT}s"
            $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '')
            if ($cleanOut) { Write-Host "      -> $cleanOut" -ForegroundColor DarkGray }

            Step "Opening VSCode"
            & code --folder-uri "vscode-remote://ssh-remote+$Alias$($go.Path)"
            StepOk $($go.Path)

            Write-Host ""
            Write-Host "    Run 'claude' in the VSCode terminal." -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "    ============================================" -ForegroundColor DarkGray
            Write-Host "    Session active -- keep this window open" -ForegroundColor Cyan
            Write-Host "    R = reconnect   Q or Enter = disconnect" -ForegroundColor DarkGray
            Write-Host "    ============================================" -ForegroundColor DarkGray
            Write-Host ""

            # Flush any keys pressed during reconnect delay so they don't immediately trigger an action
            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

            # Wait for keypress or tunnel drop
            $action = 'q'
            while (-not $bgTunnel.HasExited) {
                if ([Console]::KeyAvailable) {
                    $ch = ([Console]::ReadKey($true)).KeyChar.ToString().ToLower()
                    if ($ch -eq 'r') { $action = 'r' }
                    break
                }
                Start-Sleep -Milliseconds 500
            }
            if ($bgTunnel.HasExited) {
                $action = 'r'
                Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
            }

            # Disconnect
            Write-Host ""
            Write-Host "    Disconnecting..." -ForegroundColor DarkGray
            SshX "$CM down '$($go.Id)'" 2>$null | Out-Null
            if (-not $bgTunnel.HasExited) {
                Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
            }
            $alreadyDown = $true
            Write-Host "    .git restored on Windows." -ForegroundColor Green

            if ($action -ne 'r') { break sessionLoop }

            $alreadyDown = $false
            Write-Host ""
            Write-Host "    Reconnecting in 2s..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            Write-Host ""
        }
    } finally {
        # Runs on window close (CTRL_CLOSE_EVENT) - ensure cleanup even if window is force-closed
        if (-not $alreadyDown) {
            Write-Host ""
            Write-Host "    Disconnecting..." -ForegroundColor DarkGray
            SshX "$CM down '$($go.Id)'" 2>$null | Out-Null
            if ($bgTunnel -and -not $bgTunnel.HasExited) {
                Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
            }
            Write-Host "    .git restored on Windows." -ForegroundColor Green
            Write-Host ""
        }
    }
}
Write-Host ""
