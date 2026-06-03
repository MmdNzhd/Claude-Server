#Requires -Version 5.1
Set-StrictMode -Off

$ServerIP  = "192.168.210.240"
$Alias     = "claude-server"
$CFG_DIR   = "$env:USERPROFILE\.config\claude-connect"
$CFG_FILE  = "$CFG_DIR\connect.conf"
$CM        = '$HOME/.local/bin/claude-mount'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Die   { param($m) Write-Host "[FATAL] $m" -ForegroundColor Red;   exit 1 }
function Warn  { param($m) Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Step  { param($m) Write-Host "`n>>> $m" -ForegroundColor Cyan }
function StepOk   { param($m) Write-Host "    [OK] $m" -ForegroundColor Green }
function StepFail { param($m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

function SshX {
    param([string]$Cmd)
    $out = & ssh.exe -n `
        -o ClearAllForwardings=yes `
        -o BatchMode=yes `
        -o ConnectTimeout=10 `
        -o ServerAliveInterval=5 `
        -o ServerAliveCountMax=3 `
        $Alias $Cmd 2>&1
    return $out
}

function Tunnel-Up {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(1500, $false)
        if ($ok) { $tcp.EndConnect($ar); $tcp.Close(); return $true }
        $tcp.Close()
    } catch {}
    return $false
}

function PortOpen {
    param([int]$P)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect("127.0.0.1", $P, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(1500, $false)
        if ($ok) { $tcp.EndConnect($ar); $tcp.Close(); return $true }
        $tcp.Close()
    } catch {}
    return $false
}

function Remove-SshHostBlock {
    param([string]$HostName)
    $f = "$env:USERPROFILE\.ssh\config"
    if (-not (Test-Path $f)) { return }
    $lines  = Get-Content $f
    $result = @()
    $skip   = $false
    foreach ($ln in $lines) {
        if ($ln -match "^\s*Host\s+$HostName\s*$") { $skip = $true }
        elseif ($skip -and $ln -match "^\s*Host\s+") { $skip = $false }
        if (-not $skip) { $result += $ln }
    }
    Set-Content $f $result
}

function Load-Config {
    if (Test-Path $CFG_FILE) {
        Get-Content $CFG_FILE | ForEach-Object {
            if ($_ -match "^REMOTE_USER=(.+)$") { $script:RemoteUser = $Matches[1].Trim() }
            if ($_ -match "^LAPTOP_USER=(.+)$") { $script:LaptopUser = $Matches[1].Trim() }
        }
    }
}

function Save-Config {
    New-Item -ItemType Directory -Force -Path $CFG_DIR | Out-Null
    @("REMOTE_USER=$script:RemoteUser", "LAPTOP_USER=$script:LaptopUser") |
        Set-Content $CFG_FILE
}

function Load-Mounts {
    $raw = SshX "$CM list 2>/dev/null"
    $mounts = @()
    foreach ($line in $raw) {
        if ($line -match "^([^|]+)\|([^|]+)\|([^|]+)\|([^|]*)$") {
            $mounts += [PSCustomObject]@{
                Id    = $Matches[1].Trim()
                Label = $Matches[2].Trim()
                RPath = $Matches[3].Trim()
                LPath = $Matches[4].Trim()
            }
        }
    }
    return $mounts
}

function Show-Mounts {
    param($mounts)
    if ($mounts.Count -eq 0) {
        Write-Host "  (no projects configured)" -ForegroundColor DarkGray
        return
    }
    for ($i = 0; $i -lt $mounts.Count; $i++) {
        Write-Host ("  {0,2}.  {1,-20}  {2}" -f ($i+1), $mounts[$i].Label, $mounts[$i].LPath)
    }
}

function Pick-Mount {
    param($mounts, [string]$Prompt = "Select project number")
    if ($mounts.Count -eq 0) { return $null }
    $idx = Read-Host $Prompt
    $n   = 0
    if ([int]::TryParse($idx, [ref]$n) -and $n -ge 1 -and $n -le $mounts.Count) {
        return $mounts[$n - 1]
    }
    return $null
}

function Do-Add {
    $lpath = Read-Host "Local folder path (on this laptop)"
    $lpath = $lpath.Trim()
    $label = Read-Host "Project name/label"
    $label = $label.Trim()
    if (-not $label) { $label = (Split-Path $lpath -Leaf) }
    $id    = $label -replace "[^a-zA-Z0-9_-]", "_"
    $rpath = $lpath -replace "\\", "/"
    $out   = SshX "$CM add '$id' '$label' '$rpath' '$lpath' 2>&1"
    if ($LASTEXITCODE -eq 0) {
        StepOk "Project '$label' added (id=$id)"
    } else {
        StepFail "Add failed: $out"
    }
}

# ---------------------------------------------------------------------------
# Load saved config
# ---------------------------------------------------------------------------
$script:RemoteUser = ""
$script:LaptopUser = ""
Load-Config

# ---------------------------------------------------------------------------
# Step 1 - Check SSH on laptop
# ---------------------------------------------------------------------------
Step "Checking SSH client"
$sshBin = Get-Command ssh.exe -ErrorAction SilentlyContinue
if (-not $sshBin) { Die "ssh.exe not found. Enable OpenSSH in Windows Settings." }
StepOk "ssh.exe found at $($sshBin.Source)"

# ---------------------------------------------------------------------------
# Step 2 - Create server SSH key
# ---------------------------------------------------------------------------
Step "Checking server SSH key"
$sshDir = "$env:USERPROFILE\.ssh"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyPath = "$sshDir\id_ed25519"
if (-not (Test-Path $keyPath)) {
    Step "Generating SSH key pair"
    & ssh-keygen.exe -t ed25519 -f $keyPath -N "" -q
    if ($LASTEXITCODE -ne 0) { Die "ssh-keygen failed" }
    StepOk "Key created: $keyPath"
} else {
    StepOk "Key already exists: $keyPath"
}

# ---------------------------------------------------------------------------
# Step 3 - Write ~/.ssh/config block
# ---------------------------------------------------------------------------
Step "Writing SSH config for $Alias"
Remove-SshHostBlock $Alias
$sshConfig = "$sshDir\config"
$block = @"

Host $Alias
    HostName $ServerIP
    User $($script:RemoteUser)
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
"@
Add-Content $sshConfig $block
StepOk "SSH config updated"

# ---------------------------------------------------------------------------
# Step 4 - Connect (install key if needed, fix username on failure)
# ---------------------------------------------------------------------------
Step "Testing connection to $Alias"
if (-not $script:RemoteUser) {
    $script:RemoteUser = Read-Host "Remote username on server"
    $script:RemoteUser = $script:RemoteUser.Trim()
    Remove-SshHostBlock $Alias
    $block = @"

Host $Alias
    HostName $ServerIP
    User $($script:RemoteUser)
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
"@
    Add-Content $sshConfig $block
    Save-Config
}

$testOut = SshX "echo ok" 2>&1
if ($testOut -notmatch "ok") {
    Warn "Key not installed yet - attempting ssh-copy-id equivalent"
    $pubKey = Get-Content "$keyPath.pub"

    # Admin check
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminGroupSid = "S-1-5-32-544"
    $inAdminGroup  = ([Security.Principal.WindowsIdentity]::GetCurrent()).Groups |
        Where-Object { $_.Value -eq $adminGroupSid }

    $installCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

    Write-Host "    Trying password-based key install. Enter server password when prompted."
    & ssh.exe -o StrictHostKeyChecking=no -o BatchMode=no `
        "$($script:RemoteUser)@$ServerIP" $installCmd

    $testOut2 = SshX "echo ok" 2>&1
    if ($testOut2 -notmatch "ok") {
        Write-Host "    Connection still failing. Username wrong?" -ForegroundColor Yellow
        $newUser = Read-Host "    Enter new username (or Enter to exit)"
        if (-not $newUser) { Die "Cannot connect to server." }
        $script:RemoteUser = $newUser.Trim()
        Remove-SshHostBlock $Alias
        $block = @"

Host $Alias
    HostName $ServerIP
    User $($script:RemoteUser)
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
"@
        Add-Content $sshConfig $block
        Save-Config
        $testOut3 = SshX "echo ok" 2>&1
        if ($testOut3 -notmatch "ok") { Die "Still cannot connect as $($script:RemoteUser)." }
    }
}
StepOk "Connected as $($script:RemoteUser)"

# ---------------------------------------------------------------------------
# Step 5 - Tunnel setup
# ---------------------------------------------------------------------------
Step "Setting up reverse tunnel key"
$uidRaw = SshX "id -u" 2>&1
$uid    = [int]($uidRaw | Select-String "^\d+$" | Select-Object -First 1)
$Port   = 20000 + $uid

$laptopKey = "$sshDir\claude_laptop"
if (-not (Test-Path $laptopKey)) {
    Step "Generating tunnel key pair (claude_laptop)"
    & ssh-keygen.exe -t ed25519 -f $laptopKey -N "" -q
    if ($LASTEXITCODE -ne 0) { Die "ssh-keygen for claude_laptop failed" }
    StepOk "Tunnel key created: $laptopKey"
} else {
    StepOk "Tunnel key already exists: $laptopKey"
}

if (-not $script:LaptopUser) {
    $script:LaptopUser = $env:USERNAME
}

$laptopPub = Get-Content "$laptopKey.pub"

# Determine authorized_keys location
$inAdminGroup2 = ([Security.Principal.WindowsIdentity]::GetCurrent()).Groups |
    Where-Object { $_.Value -eq "S-1-5-32-544" }

if ($inAdminGroup2) {
    $authKeysPath = "$env:ProgramData\ssh\administrators_authorized_keys"
    $authKeysDir  = "$env:ProgramData\ssh"
} else {
    $authKeysPath = "$sshDir\authorized_keys"
    $authKeysDir  = $sshDir
}

New-Item -ItemType Directory -Force -Path $authKeysDir | Out-Null
$existingKeys = ""
if (Test-Path $authKeysPath) { $existingKeys = Get-Content $authKeysPath -Raw }
if ($existingKeys -notmatch [regex]::Escape($laptopPub.Trim())) {
    Add-Content $authKeysPath "`n$laptopPub"
    if ($inAdminGroup2) {
        & icacls.exe $authKeysPath /inheritance:r /grant "SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" | Out-Null
    }
    StepOk "Tunnel public key added to $authKeysPath"
} else {
    StepOk "Tunnel public key already in $authKeysPath"
}

# Write RemoteForward block to SSH config
Remove-SshHostBlock $Alias
$laptopKeyFwd = ($laptopKey -replace "\\", "/") -replace "^[A-Za-z]:", {"/".ToString() + $_.Value.Substring(0,1).ToLower()}
$laptopKeyFwd = $laptopKey -replace "\\", "/"
$laptopKeyFwd = $laptopKeyFwd -replace "^([A-Za-z]):", { "/$($_.Groups[1].Value.ToLower())" }

$block2 = @"

Host $Alias
    HostName $ServerIP
    User $($script:RemoteUser)
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    RemoteForward $Port localhost:22
"@
Add-Content $sshConfig $block2

# Write ~/.claude-connect.conf
$connectConf = "$env:USERPROFILE\.claude-connect.conf"
@"
LAPTOP_USER=$($script:LaptopUser)
TUNNEL_PORT=$Port
"@ | Set-Content $connectConf
StepOk "Tunnel configured: port $Port, laptop user $($script:LaptopUser)"
Save-Config

# ---------------------------------------------------------------------------
# Step 6 - Push latest claude-mount.sh if available
# ---------------------------------------------------------------------------
$mountScript = Join-Path $PSScriptRoot "..\..\server\claude-mount.sh"
$mountScript = [System.IO.Path]::GetFullPath($mountScript)
if (Test-Path $mountScript) {
    Step "Pushing claude-mount.sh to server"
    $scpOut = & scp.exe -o StrictHostKeyChecking=no -o BatchMode=yes `
        $mountScript "${Alias}:~/.local/bin/claude-mount" 2>&1
    if ($LASTEXITCODE -eq 0) {
        SshX "chmod +x ~/.local/bin/claude-mount; grep -qxF 'export PATH=\$HOME/.local/bin:\$PATH' ~/.bashrc || echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc" | Out-Null
        StepOk "claude-mount pushed and PATH updated"
    } else {
        Warn "scp of claude-mount.sh failed: $scpOut"
    }
}

# ---------------------------------------------------------------------------
# Main menu loop
# ---------------------------------------------------------------------------
while ($true) {
    Write-Host ""
    Write-Host "=== Claude Server Projects ===" -ForegroundColor Cyan
    $mounts = Load-Mounts
    Show-Mounts $mounts
    Write-Host ""
    Write-Host "  a add   e edit   d delete   c config   q quit" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-Host "Select project # or action"
    $choice = $choice.Trim().ToLower()

    switch -Regex ($choice) {
        "^q$" { exit 0 }

        "^a$" {
            Do-Add
        }

        "^e$" {
            $m = Pick-Mount $mounts "Edit project #"
            if ($null -eq $m) { Warn "Invalid selection"; continue }
            $newLabel = Read-Host "New label [$($m.Label)]"
            if (-not $newLabel) { $newLabel = $m.Label }
            $newRPath = Read-Host "New remote path [$($m.RPath)]"
            if (-not $newRPath) { $newRPath = $m.RPath }
            $newLPath = Read-Host "New local path [$($m.LPath)]"
            if (-not $newLPath) { $newLPath = $m.LPath }
            SshX "$CM rm '$($m.Id)' 2>/dev/null; $CM add '$($m.Id)' '$newLabel' '$newRPath' '$newLPath'" | Out-Null
            StepOk "Project updated"
        }

        "^d$" {
            $m = Pick-Mount $mounts "Delete project #"
            if ($null -eq $m) { Warn "Invalid selection"; continue }
            $confirm = Read-Host "Delete '$($m.Label)'? [y/N]"
            if ($confirm -match "^[yY]$") {
                SshX "$CM rm '$($m.Id)' 2>&1" | Out-Null
                StepOk "Deleted '$($m.Label)'"
            }
        }

        "^c$" {
            $newUser = Read-Host "New remote username [$($script:RemoteUser)]"
            if ($newUser) {
                $script:RemoteUser = $newUser.Trim()
                Remove-SshHostBlock $Alias
                $block3 = @"

Host $Alias
    HostName $ServerIP
    User $($script:RemoteUser)
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    RemoteForward $Port localhost:22
"@
                Add-Content $sshConfig $block3
                Save-Config
                StepOk "Username updated to $($script:RemoteUser)"
            }
        }

        default {
            $n = 0
            if (-not [int]::TryParse($choice, [ref]$n)) { Warn "Unknown input"; continue }
            if ($n -lt 1 -or $n -gt $mounts.Count) { Warn "Out of range"; continue }
            $mount = $mounts[$n - 1]
            $id    = $mount.Id
            $lpath = $mount.LPath

            Step "Mounting '$($mount.Label)'"

            # 1. Check VSCode
            $codeCmd = Get-Command code -ErrorAction SilentlyContinue
            if (-not $codeCmd) { Die "VSCode 'code' command not found in PATH." }

            # 2. Kill stale tunnel processes
            Get-Process -Name "ssh" -ErrorAction SilentlyContinue | Where-Object {
                try {
                    $wmi = Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue
                    $wmi -and ($wmi.CommandLine -match "-R\s+$Port`:localhost:22")
                } catch { $false }
            } | Stop-Process -Force -ErrorAction SilentlyContinue

            # 3. Start background tunnel
            $bgTunnel = Start-Process ssh.exe -ArgumentList @(
                "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=3",
                "-R", "${Port}:localhost:22",
                $Alias
            ) -WindowStyle Hidden -PassThru

            # 4. Wait for tunnel
            $tunnelUp = $false
            foreach ($_ in 1..6) {
                Start-Sleep -Seconds 2
                if (Tunnel-Up) { $tunnelUp = $true; break }
            }

            if (-not $tunnelUp) {
                StepFail "Reverse tunnel did not come up on port $Port"
                if ($bgTunnel -and -not $bgTunnel.HasExited) {
                    Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
                }
                exit 1
            }

            # 5. Mount via claude-mount
            $mountOut = SshX "$CM up '$id' 2>&1"
            $mountFailed = ($mountOut -match "error|fail|No such|not found|cannot|refused" -and
                            $mountOut -notmatch "already mounted")

            if ($mountFailed) {
                StepFail "Mount failed for '$id'"
                Write-Host ""
                Write-Host "  Output: $mountOut" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  Hints:" -ForegroundColor Yellow
                Write-Host "    - Is sshd running on this laptop? (Start OpenSSH Server service)"
                Write-Host "    - Is port $Port reachable? Check Windows Firewall."
                Write-Host "    - Test tunnel: ssh -v -p $Port -i ~/.ssh/claude_laptop ${LaptopUser}@localhost 'echo ok'"
                Write-Host "    - Is ~/.ssh/claude_laptop.pub in your authorized_keys?"
                Write-Host ""
                exit 1
            }

            # 6. Kill tunnel, open VSCode
            if ($bgTunnel -and -not $bgTunnel.HasExited) {
                Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
            }

            StepOk "Mount successful"
            $folderUri = "vscode-remote://ssh-remote+${Alias}${lpath}"
            & code --folder-uri $folderUri
            StepOk "VSCode opened: $lpath"

            # Mount remaining projects in background
            SshX "($CM up >/dev/null 2>&1 &); true" | Out-Null
        }
    }
}
