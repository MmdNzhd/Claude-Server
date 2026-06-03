# connect.ps1 - Claude Code launcher for Windows.
# Usage:  double-click connect.bat
#         connect.bat -Setup   (reconfigure username)

param([switch]$Setup)

$ErrorActionPreference = "Continue"
$ServerIP = "192.168.210.240"
$Alias    = "claude-server"
$CfgDir   = Join-Path $env:USERPROFILE ".config\claude-connect"
$Cfg      = Join-Path $CfgDir "connect.conf"
$SshDir   = Join-Path $env:USERPROFILE ".ssh"
$CM       = '$HOME/.local/bin/claude-mount'

function Die($m)   { Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; exit 1 }
function Warn($m)  { Write-Host "  [!] $m" -ForegroundColor DarkYellow }
function Step($m)  { Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan }
function StepOk  { param([string]$d=''); if ($d) { Write-Host " $d" -ForegroundColor Green } else { Write-Host " ok" -ForegroundColor Green } }
function StepFail{ param([string]$d=''); Write-Host " failed" -ForegroundColor Red; if ($d) { Write-Host "      -> $d" -ForegroundColor DarkGray } }

function SshX([string]$Cmd) {
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 $Alias $Cmd
}

function Tunnel-Up {
    return ((SshX "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port' 2>/dev/null && echo UP" 2>$null) -match 'UP')
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

function Load-Mounts {
    $out = @()
    foreach ($line in ((SshX "$CM status 2>/dev/null") -split "`n")) {
        if ($line.Trim() -match '^([^\|]+)\|([^\|]*)\|([^\|]+)\|(MOUNTED|OFF)$') {
            $out += [PSCustomObject]@{
                Id    = $matches[1].Trim()
                Label = $matches[2].Trim()
                Path  = $matches[3].Trim()
                On    = ($matches[4].Trim() -eq "MOUNTED")
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

function Pick-Mount($mounts, $n) {
    if ($n -match '^\d+$') {
        $i = [int]$n - 1
        if ($i -ge 0 -and $i -lt $mounts.Count) { return $mounts[$i] }
    }
    return $null
}

function Do-Add {
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

# header
Clear-Host
Write-Host ""
Write-Host "    Claude Code" -ForegroundColor White
Write-Host "    $Alias  |  $ServerIP" -ForegroundColor DarkGray
Write-Host ""

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
if (-not (Test-Path $keyA)) { ssh-keygen -t ed25519 -N '' -f $keyA -q }
if (Test-Path $keyA) { StepOk } else { StepFail "could not create key"; exit 1 }

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

# connect
Step "Connecting"
ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=6 $Alias "true" 2>$null
if ($LASTEXITCODE -eq 0) { StepOk "$RemoteUser@$ServerIP" }
if ($LASTEXITCODE -ne 0) {
    if (-not (PortOpen $ServerIP 22)) {
        StepFail "cannot reach $ServerIP - VPN connected? Server running?"
        Write-Host ""; exit 1
    }
    StepFail "auth failed - installing key"
    Write-Host ""
    Write-Host "    Enter server password (one time only):" -ForegroundColor Yellow
    Get-Content "$keyA.pub" | ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $keyCopyOk = ($LASTEXITCODE -eq 0)
    Step "Verifying connection"
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=6 $Alias "true" 2>$null
    if ($LASTEXITCODE -ne 0) {
        if (-not $keyCopyOk) { StepFail "key copy failed - wrong password?" }
        else { StepFail "still cannot connect" }
        Write-Host ""
        Warn "Cannot connect to $Alias ($RemoteUser@$ServerIP)."
        Write-Host ""
        Write-Host "    Current username: $RemoteUser" -ForegroundColor DarkGray
        $fix = (Read-Host "    Username changed? Enter new username (or Enter to exit)").Trim()
        if ($fix) {
            @("REMOTE_USER=$fix", "LAPTOP_USER=$env:USERNAME") | Set-Content -Path $Cfg -Encoding ASCII
            Remove-SshHostBlock $sshCfg $Alias
            Write-Host ""; Write-Host "    Saved. Re-run connect.bat." -ForegroundColor Green
        }
        Write-Host ""; exit 1
    }
    StepOk "$RemoteUser@$ServerIP"
}

# tunnel setup
Step "Getting tunnel port"
$uidStr = (SshX "id -u") -join ""
$Port   = 20000 + [int]($uidStr -replace '\D','')
if ($Port -le 20000) { StepFail "could not get UID from server"; exit 1 }
StepOk "port $Port"

Step "Setting up server key"
SshX "test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q" 2>$null | Out-Null
$PubB = (SshX "cat ~/.ssh/claude_laptop.pub").Trim()
if (-not $PubB) { StepFail "could not read server key"; exit 1 }
$adminSid    = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'
$curGroups   = [System.Security.Principal.WindowsIdentity]::GetCurrent().Groups
$isAdminUser = $curGroups -and ($curGroups | Where-Object { $_.Value -eq $adminSid.Value })
$authKeys    = if ($isAdminUser) { Join-Path $env:ProgramData "ssh\administrators_authorized_keys" } else { Join-Path $SshDir "authorized_keys" }
if (-not (Test-Path $authKeys)) { New-Item -ItemType File -Path $authKeys -Force | Out-Null }
if ((Get-Content $authKeys -ErrorAction SilentlyContinue) -notcontains $PubB) { Add-Content -Path $authKeys -Value $PubB -Encoding ASCII }
if ($isAdminUser) { icacls $authKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null | Out-Null }
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
SshX "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\n' '$LaptopUser' '$Port' > ~/.claude-connect.conf" 2>$null | Out-Null
StepOk "laptop=$LaptopUser port=$Port"

# push claude-mount if available
$src = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..\server\claude-mount.sh"))
if (Test-Path $src) {
    SshX "mkdir -p ~/.local/bin" 2>$null | Out-Null
    scp -o BatchMode=yes -o ConnectTimeout=10 -q $src "${Alias}:~/.local/bin/claude-mount" 2>$null
    SshX "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc" 2>$null | Out-Null
}

Write-Host ""
Write-Host "    Ready" -ForegroundColor Green
Write-Host ""

# mount helpers
$mounts = @(Load-Mounts)
$go = $null

while (-not $go) {
    if ($mounts.Count -eq 0) {
        $go = Do-Add
        if (-not $go) { Die "Could not add project." }
        break
    }

    Show-Mounts $mounts
    $c = (Read-Host "    >").Trim().ToLower()
    Write-Host ""

    if ($c -match '^\d+$') {
        $m = Pick-Mount $mounts $c
        if (-not $m) { Warn "Not found."; continue }
        $go = [PSCustomObject]@{ Id = $m.Id; Path = $m.Path }
    } else { switch ($c) {
        "a" {
            $r = Do-Add
            if ($r) { $go = $r } else { $mounts = @(Load-Mounts) }
        }
        "e" {
            $cur = Pick-Mount $mounts (Read-Host "    Edit number").Trim()
            if (-not $cur) { Warn "Not found."; continue }
            $curR = (SshX "grep REMOTE_PATH ~/.claude-mounts.d/$($cur.Id).conf" 2>$null) -replace 'REMOTE_PATH=|"',''
            Write-Host ""
            $nLbl = (Read-Host "    Name  [$($cur.Label)]").Trim(); if (-not $nLbl) { $nLbl = $cur.Label }
            $nR   = (Read-Host "    Path  [$curR]").Trim() -replace '\\','/'; if (-not $nR) { $nR = $curR }
            $nL   = (Read-Host "    Local [$($cur.Path)]").Trim(); if (-not $nL) { $nL = $cur.Path }
            $editOut = (SshX "$CM edit '$($cur.Id)' '$nLbl' '$nR' '$nL'" 2>&1) | Out-String
            if ($LASTEXITCODE -ne 0) { Warn $editOut.Trim() }
            $mounts = @(Load-Mounts)
        }
        "d" {
            $m = Pick-Mount $mounts (Read-Host "    Delete number").Trim()
            if (-not $m) { Warn "Not found."; continue }
            if ((Read-Host "    Delete '$($m.Label)'? [y/N]").Trim().ToLower() -eq "y") {
                $rmOut = (SshX "$CM rm '$($m.Id)'" 2>&1) | Out-String
                if ($LASTEXITCODE -ne 0) { Warn $rmOut.Trim() }
                $mounts = @(Load-Mounts)
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
        Write-Host ""; exit 1
    }

    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${Port}:localhost:22" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Step "Mounting files"
    $bgTunnel = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList @(
        "-N", "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
        "-R", "$Port`:localhost:22", $Alias)

    $up = $false
    foreach ($i in 1..6) { Start-Sleep -Seconds 2; if (Tunnel-Up) { $up = $true; break } }

    if (-not $up) {
        StepFail "could not reach laptop on port 22"
        Write-Host "    -> Is OpenSSH Server running?  Get-Service sshd" -ForegroundColor DarkGray
        Write-Host ""; exit 1
    }

    $mountOut = (SshX "$CM up '$($go.Id)' 2>&1") | Out-String
    $mountOk  = $LASTEXITCODE -eq 0 -and $mountOut -notmatch 'FAILED|No tunnel|not configured'

    if (-not $mountOk) {
        StepFail $mountOut.Trim()
        Write-Host "    -> Is OpenSSH Server running?  Get-Service sshd" -ForegroundColor DarkGray
        Write-Host "    -> Is the project path correct? Use 'e edit' to fix it." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    Debug: on server run:" -ForegroundColor DarkGray
        Write-Host "      ssh -v -p $Port -i ~/.ssh/claude_laptop ${LaptopUser}@localhost 'echo ok'" -ForegroundColor DarkGray
        Write-Host ""; exit 1
    }

    if ($bgTunnel -and -not $bgTunnel.HasExited) {
        Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
    }
    StepOk
    if ($mountOut.Trim()) { Write-Host "    $($mountOut.Trim())" -ForegroundColor DarkGray }

    Step "Opening VSCode"
    & code --folder-uri "vscode-remote://ssh-remote+$Alias$($go.Path)"
    StepOk $($go.Path)

    Write-Host ""
    Write-Host "    Run 'claude' in the VSCode terminal." -ForegroundColor DarkGray
    SshX "($CM up >/dev/null 2>&1 &); true" 2>$null | Out-Null
}
Write-Host ""
