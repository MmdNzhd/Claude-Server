# connect.ps1 - Designer Connect launcher for Windows.
# Usage:  double-click connect.bat
#         connect.bat -Setup   (reconfigure laptop path)

param([switch]$Setup)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Setup) { $elevArgs += '-Setup' }
    Start-Process powershell -Verb RunAs -ArgumentList $elevArgs
    exit
}

$ErrorActionPreference = "Continue"
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
    Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}

$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$ServerIP   = "192.168.210.240"
$Alias      = "claude-server"
$RemoteUser = "designer"
$CfgDir     = Join-Path $env:USERPROFILE ".config\claude-connect-designer"
$Cfg        = Join-Path $CfgDir "connect.conf"
$SshDir     = Join-Path $env:USERPROFILE ".ssh"
$CM         = '$HOME/.local/bin/claude-mount'
$NovncPort  = 27015
$MountId    = "laptop"

function Die($m)  {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog "FAIL DIE: $m" 'ERROR' }
    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor DarkYellow }
function Step($m) { Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan }
function StepOk  {
    param([string]$d='')
    if ($d) { Write-Host " $d" -ForegroundColor Green } else { Write-Host " ok" -ForegroundColor Green }
    foreach ($fx in $script:pendingFixes) { Write-Host "      -> fixed: $fx" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
}
function StepFail {
    param([string]$d='')
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog ("FAIL STEP name={0} detail={1}" -f $script:currentStepName, $d) 'ERROR' }
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
    if ($script:LaptopUser -and $script:LaptopUser -ne $env:USERNAME) {
        icacls $path /grant "$($script:LaptopUser)`:F" 2>$null | Out-Null
    }
    if ($out -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "$label permissions" }
}

function Install-ServerKey([string]$pub, [bool]$ForceRestart = $false) {
    $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    $userFile  = Join-Path $SshDir "authorized_keys"

    $adminDir = Split-Path $adminFile
    if (Test-Path $adminDir) {
        if (-not (Test-Path $adminFile)) { New-Item -ItemType File -Path $adminFile -Force | Out-Null }
        $_adminOut = (icacls $adminFile 2>$null) -join ' '
        icacls $adminFile /reset 2>$null | Out-Null
        icacls $adminFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null | Out-Null
        if ($_adminOut -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "administrators_authorized_keys permissions" }
    }

    foreach ($akFile in @($adminFile, $userFile)) {
        if (-not (Test-Path (Split-Path $akFile))) { continue }
        if (-not (Test-Path $akFile)) { New-Item -ItemType File -Path $akFile -Force -ErrorAction SilentlyContinue | Out-Null }
        if (-not (Test-Path $akFile)) { continue }
        $lines = @(Get-Content $akFile -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $restricted = "from=`"127.0.0.1,::1`" $pub"
        # Remove any existing entry for this key (restricted or unrestricted), then re-add with restriction
        $lines = @($lines | Where-Object { $_ -notlike "*$pub*" })
        $lines += $restricted
        Set-Content -Path $akFile -Value $lines -Encoding ASCII
        if ($akFile -eq $userFile) { Repair-SshPerm $akFile "authorized_keys" }
    }

    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($ForceRestart -and $sshdSvc -and $sshdSvc.Status -eq 'Running') {
        Restart-Service sshd -ErrorAction SilentlyContinue
        $deadline = (Get-Date).AddSeconds(20)
        $sshdReady = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    if ($tcp.BeginConnect('127.0.0.1', 22, $null, $null).AsyncWaitHandle.WaitOne(1000)) {
                        $tcp.Close(); $sshdReady = $true; break
                    }
                    $tcp.Close()
                } catch {}
            }
        }
        if (-not $sshdReady) { $script:pendingFixes += "sshd restart failed - run connect.bat as administrator" }
    } elseif (-not $sshdSvc -or $sshdSvc.Status -ne 'Running') {
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function SshX([string]$Cmd) {
    # Base64-encode: a bare native-exe argument with embedded quotes can be mangled by
    # PowerShell's argument marshaling to ssh.exe (seen in production as "unexpected EOF
    # while looking for matching `""). A base64 blob has no shell-special characters.
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Cmd))
    $wrapped = "echo $b64|base64 -d|bash"
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $Alias $wrapped
}

function Test-Tunnel {
    $r = ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=8 `
             -o ServerAliveInterval=3 -o ServerAliveCountMax=2 `
             $Alias "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port' 2`>/dev/null && echo UP" 2>$null
    return ($r -match 'UP')
}

$_gitMode = Join-Path $script:ConnectScriptDir 'git-mode.ps1'
if (-not (Test-Path $_gitMode)) {
    $_gitMode = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'git-mode.ps1'
}
if (-not (Test-Path $_gitMode)) {
    $_gitMode = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'git-mode.ps1'
}
if (-not (Test-Path $_gitMode)) {
    Die "git-mode.ps1 not found - re-copy the full designer package"
}
. $_gitMode

$_connectUi = Join-Path $script:ConnectScriptDir 'connect-ui.ps1'
if (-not (Test-Path $_connectUi)) {
    $_connectUi = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'connect-ui.ps1'
}
if (-not (Test-Path $_connectUi)) {
    $_connectUi = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'connect-ui.ps1'
}
if (Test-Path $_connectUi) {
    . $_connectUi
    if (Get-Command Initialize-ConnectLog -ErrorAction SilentlyContinue) {
        Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version 'designer'
    }
}
# Single-instance: shares Global\ClaudeConnect mutex with main connect (one UI per PC).
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
        else { exit 2 }
    }
}

function Test-NovncLocal {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ok  = $tcp.BeginConnect('127.0.0.1', $NovncPort, $null, $null).AsyncWaitHandle.WaitOne(2000)
        $tcp.Close()
        return $ok
    } catch { return $false }
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

New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
New-Item -ItemType Directory -Force -Path $SshDir  | Out-Null

$_dirOut   = (icacls $SshDir 2>$null) -join ' '
$_dirFixed = $_dirOut -match '\(I\)|Everyone|BUILTIN\\Users'
icacls $SshDir /reset 2>$null | Out-Null
icacls $SshDir /inheritance:r /grant "$env:USERNAME`:(OI)(CI)F" 2>$null | Out-Null

Clear-Host
Write-Host ""
Write-Host "    Designer Connect" -ForegroundColor White
Write-Host "    $Alias  |  $ServerIP" -ForegroundColor DarkGray
Write-Host ""
if ($_dirFixed) { Write-Host "      -> fixed: .ssh directory permissions" -ForegroundColor DarkGray; Write-Host "" }

if ($Setup -or -not (Test-Path $Cfg)) {
    Write-Host "  First-time setup" -ForegroundColor Cyan
    Write-Host ""
    $LaptopPath = (Read-Host "    Folder on your laptop to share (e.g. D:\Designs)").Trim() -replace '\\','/'
    if (-not $LaptopPath) { Die "Laptop path is required." }
    @("LAPTOP_USER=$env:USERNAME", "LAPTOP_PATH=$LaptopPath") | Set-Content -Path $Cfg -Encoding ASCII
    Write-Host ""
}
$conf = @{}
Get-Content $Cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $conf[$matches[1]] = $matches[2] } }
$LaptopUser = $conf["LAPTOP_USER"]
$LaptopPath = $conf["LAPTOP_PATH"]
if (-not $LaptopUser) { Die "Config missing LAPTOP_USER. Re-run connect.bat -Setup to reconfigure." }
if (-not $LaptopPath) { Die "Config missing LAPTOP_PATH. Re-run connect.bat -Setup to reconfigure." }
$script:LaptopUser = $LaptopUser
if ($LaptopUser -and (Test-Path "C:\Users\$LaptopUser")) {
    $SshDir = Join-Path "C:\Users\$LaptopUser" ".ssh"
}
New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
icacls $SshDir /reset 2>$null | Out-Null
icacls $SshDir /inheritance:r /grant "$env:USERNAME`:(OI)(CI)F" 2>$null | Out-Null
if ($LaptopUser -and $LaptopUser -ne $env:USERNAME) {
    icacls $SshDir /grant "$LaptopUser`:(OI)(CI)F" 2>$null | Out-Null
}

Step "Laptop SSH key"
$keyA = Join-Path $SshDir "id_ed25519"
if (-not (Test-Path $keyA)) { ssh-keygen -t ed25519 -N '""' -f $keyA -q }
if (Test-Path $keyA) {
    Repair-SshPerm $keyA "SSH private key"
    StepOk
} else { StepFail "could not create key"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }

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
icacls $sshCfg /reset 2>$null | Out-Null
icacls $sshCfg /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null

$connected = $false
$needsKey  = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
    $sw.Stop(); $connT = [math]::Round($sw.Elapsed.TotalSeconds, 1)
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
    ssh-keygen -R $ServerIP 2>$null | Out-Null
    Write-Host "    Enter designer password (one time only):" -ForegroundColor Yellow
    $pubKeyContent = (Get-Content "$keyA.pub").Trim() -replace "'", "'\''"
    ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $keyCopyOk = ($LASTEXITCODE -eq 0)
    Step "Verifying connection"
    $verifySW = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
    $verifySW.Stop(); $verifyT = [math]::Round($verifySW.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -ne 0) {
        if (-not $keyCopyOk) { StepFail "key copy failed after ${verifyT}s - wrong password?" }
        else { StepFail "still cannot connect after ${verifyT}s" }
        Warn "Cannot connect - user=$RemoteUser  host=$ServerIP"
        Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
    }
    StepOk "$RemoteUser@$ServerIP"
}

Step "Getting tunnel port + server key"
$initOut = (SshX "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub") -join "`n"
$lines   = ($initOut -replace "`r",'') -split "`n" | Where-Object { $_.Trim() -ne '' }
$uidStr  = ($lines | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1) -replace '\D',''
$Port    = 20000 + [int]$uidStr
$PubB    = ([string](($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1) + '')).Trim()
if ($Port -le 20000 -or $Port -gt 65535) { StepFail "could not get UID from server"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
if (-not $PubB)      { StepFail "could not read server key";     Read-Host "    Press Enter to close" | Out-Null; exit 1 }
StepOk "port $Port"

Step "Setting up server key"
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
Push-ServerConnectConf
StepOk "laptop=$LaptopUser port=$Port git=$(Get-GitMode)"

if (Resolve-ServerScriptDir -ConnectScriptDir $script:ConnectScriptDir) {
    Push-ClaudeServerScripts -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias | Out-Null
}

Write-Host ""
Write-Host "    Ready" -ForegroundColor Green
Write-Host ""

$MountLpath = "/home/$RemoteUser/mounts/$MountId"
$existingMount = (SshX "$CM list 2`>/dev/null") | Where-Object { $_ -match "^${MountId}\|" } | Select-Object -First 1
$cleanPath = $LaptopPath -replace "'", "-"
if (-not $existingMount) {
    Step "Configuring laptop mount"
    $addEc = 0
    if (Get-Command Invoke-SshXChecked -ErrorAction SilentlyContinue) {
        $addEc = Invoke-SshXChecked -RemoteCmd "$CM add '$MountId' 'Laptop' '$cleanPath' '$MountLpath'" -Label 'DESIGNER_MOUNT_ADD'
    } else {
        $null = SshX "$CM add '$MountId' 'Laptop' '$cleanPath' '$MountLpath'" 2>$null
        $addEc = [int]$global:LASTEXITCODE
        if ($addEc -ne 0) { Warn "DESIGNER_MOUNT_ADD fail exit=$addEc" }
    }
    if ($addEc -eq 0) { StepOk $MountLpath } else { StepFail "mount add exit=$addEc" }
} elseif ($Setup) {
    Step "Updating laptop mount path"
    $editEc = 0
    if (Get-Command Invoke-SshXChecked -ErrorAction SilentlyContinue) {
        $editEc = Invoke-SshXChecked -RemoteCmd "$CM edit '$MountId' 'Laptop' '$cleanPath' '$MountLpath'" -Label 'DESIGNER_MOUNT_EDIT'
    } else {
        $null = SshX "$CM edit '$MountId' 'Laptop' '$cleanPath' '$MountLpath'" 2>$null
        $editEc = [int]$global:LASTEXITCODE
        if ($editEc -ne 0) { Warn "DESIGNER_MOUNT_EDIT fail exit=$editEc" }
    }
    if ($editEc -eq 0) { StepOk $cleanPath } else { StepFail "mount edit exit=$editEc" }
} else {
    Step "Laptop mount"
    StepOk "already configured"
}

Step "Checking SSH service"
$svc = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $svc) {
    StepFail "OpenSSH Server not installed"
    Write-Host "    OpenSSH Server not found - installing now..." -ForegroundColor Yellow
    $installed = $false
    $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wuSvc -and $wuSvc.Status -ne 'Running') {
        Write-Host "    Starting Windows Update service for install..." -ForegroundColor DarkGray
        Start-Service wuauserv -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
    }
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
        Write-Host "    OpenSSH Server installed ok (via Windows Capability)." -ForegroundColor Green
        $installed = $true
    } catch { Write-Host "    Windows Capability install failed: $($_.Exception.Message)" -ForegroundColor DarkGray }
    if (-not $installed) {
        Write-Host "    Trying winget fallback..." -ForegroundColor DarkGray
        try {
            $null = Get-Command winget -ErrorAction Stop
            & winget install --id Microsoft.OpenSSH.Beta -e --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            $svc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($svc) { Write-Host "    OpenSSH Server installed ok (via winget)." -ForegroundColor Green; $installed = $true }
        } catch { Write-Host "    winget fallback failed: $($_.Exception.Message)" -ForegroundColor DarkGray }
    }
    if (-not $installed) { Die "Could not auto-install OpenSSH Server. Manual fix: Settings -> Apps -> Optional Features -> OpenSSH Server" }
    Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service sshd -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') { Die "Could not start sshd after install. Run as admin: Start-Service sshd" }
    Write-Host "    sshd started ok." -ForegroundColor Green
    if ($PubB) { Install-ServerKey $PubB }
} elseif ($svc.Status -ne 'Running') {
    StepFail "OpenSSH Server not running"
    Write-Host "    Trying to start sshd..." -ForegroundColor Yellow
    try {
        Start-Service sshd -ErrorAction Stop
        Start-Sleep -Seconds 1
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Host "    sshd started ok." -ForegroundColor Green
        } else {
            Die "Could not start sshd. Run as admin: Start-Service sshd"
        }
    } catch { Die "Error starting sshd: $($_.Exception.Message)" }
} else { StepOk }

$fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    Write-Host "    [!] Firewall rule for SSH missing - adding..." -ForegroundColor Yellow
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
        -ErrorAction SilentlyContinue | Out-Null
} elseif ($fwRule.Enabled.ToString() -ne 'True') {
    Write-Host "    [!] Firewall rule for SSH was disabled - enabling..." -ForegroundColor Yellow
    Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
}

$novncOpened = $false

:mainLoop while ($true) {
$alreadyDown  = $false
$bgTunnel     = $null
$autoFixCount = 0

try {
    :sessionLoop while ($true) {
        if ($bgTunnel -and -not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
        }

        Step "Starting SSH tunnel"
        $bgTunnel = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList @(
            "-N", "-o", "ExitOnForwardFailure=no",
            "-o", "ServerAliveInterval=20", "-o", "ServerAliveCountMax=5",
            "-R", "$Port`:localhost:22",
            "-L", "127.0.0.1:${NovncPort}:127.0.0.1:${NovncPort}",
            $Alias)
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
            if ($tunnelMsg) { Warn $tunnelMsg }
            elseif (-not (PortOpen $ServerIP 22)) { Warn "Server unreachable - VPN disconnected?" }
            else { Warn "Check Windows Firewall - port 22 must allow inbound connections" }
            Write-Host ""
            Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
            $rk = Read-RetryQuitKey
            if ($rk -eq 'r') { Write-Host ""; continue }
            Push-ServerConnectConf -ClearActiveMount
            $alreadyDown = $true; break sessionLoop
        }

        if (Get-Command Invoke-SshXChecked -ErrorAction SilentlyContinue) { [void](Invoke-SshXChecked -RemoteCmd "$CM recover" -Label 'DESIGNER_MOUNT_RECOVER') } else { $null = SshX "$CM recover" 2>$null; if ($global:LASTEXITCODE -ne 0) { Warn "DESIGNER_MOUNT_RECOVER fail exit=$($global:LASTEXITCODE)" } }
        if (-not (Test-Tunnel)) {
            Write-Host "      -> tunnel dropped during recover, restarting..." -ForegroundColor DarkGray
            continue sessionLoop
        }

        Push-ServerConnectConf -ActiveMount $MountId

        Step "Mounting files"
        $mountSW  = [System.Diagnostics.Stopwatch]::StartNew()
        $mountResult = Invoke-MountProject -ProjectId $MountId -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias
        $mountOut = $mountResult.Out
        $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
        $mountOk  = $mountResult.Ok
        Show-MountGitWarn $mountOut

        if (-not $mountOk -and $mountOut -match 'key auth failed|connection reset|reset by peer|publickey|Permission denied' -and $autoFixCount -lt 3) {
            $autoFixCount++
            Write-Host " retrying (attempt $autoFixCount/3)..." -ForegroundColor DarkGray
            if ($mountOut -match 'connection reset|reset by peer') {
                Warn "Connection reset - killing stale mounts, fixing firewall, restarting sshd"
                SshX 'pkill -u "$USER" sshfs 2>/dev/null; true' 2>$null | Out-Null
                $fw = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
                if (-not $fw) {
                    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
                        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                        -ErrorAction SilentlyContinue | Out-Null
                    $script:pendingFixes += "SSH firewall rule created"
                } elseif ($fw.Enabled.ToString() -ne 'True' -or $fw.Profile.ToString() -notmatch 'Any') {
                    Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Profile Any -ErrorAction SilentlyContinue
                    $script:pendingFixes += "SSH firewall rule fixed"
                }
            } else {
                Warn "Key rejected - reinstalling server key and restarting sshd"
            }
            $newPub = ((SshX "cat ~/.ssh/claude_laptop.pub") -join '').Trim()
            if ($newPub) {
                Install-ServerKey $newPub -ForceRestart $true
                if (-not (Test-Tunnel)) {
                    Write-Host ""; Warn "Tunnel dropped after sshd restart - reconnecting..."
                    continue
                }
                Step "Mounting files"
                $mountSW  = [System.Diagnostics.Stopwatch]::StartNew()
                $mountResult = Invoke-MountProject -ProjectId $MountId -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias
                $mountOut = $mountResult.Out
                $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
                $mountOk  = $mountResult.Ok
            }
        }

        if (-not $mountOk) {
            StepFail $mountOut.Trim()
            if ($mountOut -match 'No such file|not found|cannot find') {
                Warn "Path not found on laptop. Re-run connect.bat -Setup to correct the path."
            }
            Write-Host ""
            Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
            $rk = Read-RetryQuitKey
            if ($rk -eq 'r') { Write-Host ""; continue }
            Push-ServerConnectConf -ClearActiveMount
            $alreadyDown = $true; break sessionLoop
        }

        StepOk "${mountT}s"
        $script:ActiveProjectId = $MountId
        $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '' -replace '^mounted:\s*', '')
        $cleanOut = (($cleanOut -split '\r?\n')[0]).Trim()
        if ($cleanOut -and $cleanOut -notmatch '^warn:') { Write-Host "      -> $cleanOut" -ForegroundColor DarkGray }

        if (-not $novncOpened) {
            Step "Opening noVNC"
            if (Test-NovncLocal) {
                Start-Process "http://localhost:${NovncPort}/vnc.html"
                StepOk "http://localhost:${NovncPort}/vnc.html"
                $novncOpened = $true
            } else {
                StepFail "noVNC port $NovncPort not reachable on localhost"
                Warn "VNC stack may not be running. Ask admin: ssh smart@$ServerIP sudo designer-start start"
                Warn "Fallback (LAN only): http://${ServerIP}:${NovncPort}/vnc.html"
            }
        }

        Write-Host ""
        Write-Host "    ============================================" -ForegroundColor DarkGray
        Write-Host "    Session active -- keep this window open" -ForegroundColor Cyan
        Write-Host "    Files mounted at: $MountLpath" -ForegroundColor DarkCyan
        Write-Host "    G = git mode   R = reconnect   Q or Enter = disconnect" -ForegroundColor DarkGray
        Write-Host "    ============================================" -ForegroundColor DarkGray
        Write-Host ""

        # Flush buffered keypresses before entering wait loop
        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

        # VK fallback ONLY for null/control KeyChar - never Persian printable non-ASCII (ض on Q).
        $action = ''
        $gotKey = $false
        while (-not $bgTunnel.HasExited) {
            if ([Console]::KeyAvailable) {
                $ki = [Console]::ReadKey($true)
                $kc = $ki.KeyChar.ToString()
                $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
                $ascii = ($code -ge 32 -and $code -le 126)
                $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
                $resolved = ''
                if ($letter -eq 'r' -or ($useVk -and $ki.Key -eq [ConsoleKey]::R)) { $resolved = 'r' }
                elseif ($letter -eq 'g' -or ($useVk -and $ki.Key -eq [ConsoleKey]::G)) { $resolved = 'g' }
                elseif ($letter -eq 'q' -or ($useVk -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $resolved = 'q' }
                if (-not $resolved) { continue }
                $action = $resolved
                $gotKey = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $gotKey -and $bgTunnel.HasExited) {
            # Drain any key the user pressed while the tunnel was dying
            if ([Console]::KeyAvailable) {
                $ki = [Console]::ReadKey($true)
                $kc = $ki.KeyChar.ToString()
                $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
                $ascii = ($code -ge 32 -and $code -le 126)
                $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
                if ($letter -eq 'r' -or ($useVk -and $ki.Key -eq [ConsoleKey]::R)) { $action = 'r' }
                elseif ($letter -eq 'q' -or ($useVk -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                else { $action = 'r' }  # ignore non-command (incl. Persian); auto-recover
            } else {
                $action = 'r'
                Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
            }
        }
        if (-not $action) { continue sessionLoop }

        if ($action -eq 'g') {
            Configure-GitMode
            continue sessionLoop
        }

        Write-Host ""
        Write-Host "    Disconnecting..." -ForegroundColor DarkGray
        if (Get-Command Invoke-SshXChecked -ErrorAction SilentlyContinue) { [void](Invoke-SshXChecked -RemoteCmd "$CM down '$MountId'" -Label 'DESIGNER_MOUNT_DOWN') } else { $null = SshX "$CM down '$MountId'" 2>$null; if ($global:LASTEXITCODE -ne 0) { Warn "DESIGNER_MOUNT_DOWN fail exit=$($global:LASTEXITCODE)" } }
        Push-ServerConnectConf -ClearActiveMount
        if (-not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
        }
        $alreadyDown = $true

        if ($action -ne 'r') { break sessionLoop }

        $alreadyDown  = $false
        $autoFixCount = 0
        Write-Host ""
        Write-Host "    Reconnecting in 2s..." -ForegroundColor Cyan
        Start-Sleep -Seconds 2
        Write-Host ""
    }
} finally {
    # Runs on normal exit, Ctrl+C, or exceptions (NOT on force-close via window X button)
    if (-not $alreadyDown) {
        Write-Host ""
        Write-Host "    Disconnecting..." -ForegroundColor DarkGray
        if (Get-Command Invoke-SshXChecked -ErrorAction SilentlyContinue) { [void](Invoke-SshXChecked -RemoteCmd "$CM down '$MountId'" -Label 'DESIGNER_MOUNT_DOWN') } else { $null = SshX "$CM down '$MountId'" 2>$null; if ($global:LASTEXITCODE -ne 0) { Warn "DESIGNER_MOUNT_DOWN fail exit=$($global:LASTEXITCODE)" } }
        Push-ServerConnectConf -ClearActiveMount
        Write-Host ""
    }
    if ($bgTunnel -and -not $bgTunnel.HasExited) {
        Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
    }
    if (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue) { Exit-ConnectSingleInstance }
elseif ($script:ConnectInstanceMutex) {
    try { $script:ConnectInstanceMutex.ReleaseMutex() } catch { }
    try { $script:ConnectInstanceMutex.Dispose() } catch { }
    $script:ConnectInstanceMutex = $null
}
}

# Flush buffered keys before post-disconnect menu
while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

Write-Host ""
Write-Host "    Disconnected. What would you like to do?" -ForegroundColor Cyan
Write-Host "    C = connect again   X = exit" -ForegroundColor DarkGray
Write-Host ""

$choice = ""
while ($choice -ne "c" -and $choice -ne "x") {
    if ([Console]::KeyAvailable) {
        $ki = [Console]::ReadKey($true)
        $kc = $ki.KeyChar.ToString()
        $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
        $ascii = ($code -ge 32 -and $code -le 126)
        $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
        $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
        if ($letter -eq 'c' -or ($useVk -and $ki.Key -eq [ConsoleKey]::C)) {
            $choice = 'c'
            Write-Host "    Reconnecting..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            Write-Host ""
            continue mainLoop
        } elseif ($letter -eq 'x' -or ($useVk -and $ki.Key -eq [ConsoleKey]::X)) {
            $choice = 'x'
            Write-Host "    Exiting..." -ForegroundColor DarkGray
            break mainLoop
        }
    } else { Start-Sleep -Milliseconds 100 }
}

} # end :mainLoop
Write-Host ""

if (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue) { Exit-ConnectSingleInstance }
elseif ($script:ConnectInstanceMutex) {
    try { $script:ConnectInstanceMutex.ReleaseMutex() } catch { }
    try { $script:ConnectInstanceMutex.Dispose() } catch { }
    $script:ConnectInstanceMutex = $null
}
