# connect.ps1 - Claude Code launcher for Windows.
# connect.bat invariant: g git (menu footer lives in connect-ui.ps1)
# Usage:  double-click connect.bat
#         connect.bat -Setup   (reconfigure username)

param(
    [switch]$Setup,
    [switch]$AdminFix,
    [ValidateSet('cursor','code','vscode')][string]$Ide = ''
)

$ErrorActionPreference = "Continue"
$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Dot-SourceSibling {
    param([string]$Name)
    foreach ($base in @($script:ConnectScriptDir, (Split-Path $script:ConnectScriptDir -Parent), (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent))) {
        $p = Join-Path $base $Name
        if (Test-Path $p) { return $p }
    }
    return $null
}

$script:RunAdminFix = [bool]$AdminFix

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
    Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}
$ServerIP = "192.168.210.240"
$Alias    = "claude-server"
$script:ConnectVersion = '20260703.12'
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

$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Shared editor launch (dot-sourced by all Windows connect launchers)
$_editorLaunch = Join-Path $script:ConnectScriptDir 'editor-launch.ps1'
if (-not (Test-Path $_editorLaunch)) {
    $_editorLaunch = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'editor-launch.ps1'
}
if (-not (Test-Path $_editorLaunch)) {
    $_editorLaunch = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'editor-launch.ps1'
}
if (-not (Test-Path $_editorLaunch)) {
    Die "editor-launch.ps1 not found - re-copy the full windows package"
}
. $_editorLaunch

$_gitMode = Join-Path $script:ConnectScriptDir 'git-mode.ps1'
if (-not (Test-Path $_gitMode)) {
    $_gitMode = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'git-mode.ps1'
}
if (-not (Test-Path $_gitMode)) {
    $_gitMode = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'git-mode.ps1'
}
if (-not (Test-Path $_gitMode)) {
    Die "git-mode.ps1 not found - re-copy the full windows package"
}
. $_gitMode

$_cursorAuth = Join-Path $script:ConnectScriptDir 'cursor-auth-laptop.ps1'
if (-not (Test-Path $_cursorAuth)) {
    $_cursorAuth = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'cursor-auth-laptop.ps1'
}
if (-not (Test-Path $_cursorAuth)) {
    $_cursorAuth = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'cursor-auth-laptop.ps1'
}
if (Test-Path $_cursorAuth) { . $_cursorAuth }

$_connectUi = Dot-SourceSibling 'connect-ui.ps1'
if (-not $_connectUi) { Die 'connect-ui.ps1 not found - re-copy the full windows package' }
. $_connectUi

function Repair-SshPerm([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { return }
    $out = (icacls $path 2>$null) -join ' '
    icacls $path /reset 2>$null | Out-Null
    icacls $path /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null
    # When elevated as a different admin account, also grant the actual laptop user access
    if ($script:LaptopUser -and $script:LaptopUser -ne $env:USERNAME) {
        icacls $path /grant "$($script:LaptopUser)`:F" 2>$null | Out-Null
    }
    if ($out -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "$label permissions" }
}

function Install-ServerKey([string]$pub, [bool]$ForceRestart = $false, [switch]$UserOnly) {
    $userFile = Join-Path $SshDir "authorized_keys"

    if (-not $UserOnly) {
        $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
        $adminDir = Split-Path $adminFile
        if (Test-Path $adminDir) {
            if (-not (Test-Path $adminFile)) { New-Item -ItemType File -Path $adminFile -Force | Out-Null }
            $_adminOut = (icacls $adminFile 2>$null) -join ' '
            icacls $adminFile /reset 2>$null | Out-Null
            icacls $adminFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null | Out-Null
            if ($_adminOut -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "administrators_authorized_keys permissions" }
        }
    }

    $targets = @($userFile)
    if (-not $UserOnly) {
        $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
        if (Test-Path (Split-Path $adminFile)) { $targets = @($adminFile) + $targets }
    }

    foreach ($akFile in $targets) {
        if (-not (Test-Path (Split-Path $akFile))) { continue }
        if (-not (Test-Path $akFile)) { New-Item -ItemType File -Path $akFile -Force -ErrorAction SilentlyContinue | Out-Null }
        if (-not (Test-Path $akFile)) { continue }
        $lines = @(Get-Content $akFile -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        # Remove any existing entry for this key (restricted or not), then add with from= restriction
        $restricted = "from=`"127.0.0.1,::1`" $pub"
        $lines = @($lines | Where-Object { $_ -notlike "*$pub*" })
        $lines += $restricted
        Set-Content -Path $akFile -Value $lines -Encoding ASCII
        if ($akFile -eq $userFile) { Repair-SshPerm $akFile "authorized_keys" }
    }

    # Always restart sshd when forced (e.g. after key rejection).
    # administrators_authorized_keys requires a restart on some Windows configurations.
    # On normal first-time setup, only start if stopped (no unnecessary restart).
    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $UserOnly -and $ForceRestart -and $sshdSvc -and $sshdSvc.Status -eq 'Running') {
        Write-Host "      -> sshd: restarting..." -ForegroundColor DarkGray
        Restart-Service sshd -ErrorAction SilentlyContinue
        # Wait until sshd is actually accepting connections (up to 20s).
        # A fixed 5s sleep races on slower machines and causes immediate retry failure.
        $deadline = (Get-Date).AddSeconds(20)
        $sshdReady = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    if ($tcp.BeginConnect('127.0.0.1', 22, $null, $null).AsyncWaitHandle.WaitOne(1000)) {
                        $tcp.Close(); $sshdReady = $true
                        Write-Host "      -> sshd: ready" -ForegroundColor DarkGray
                        break
                    }
                    $tcp.Close()
                } catch {}
            }
        }
        if (-not $sshdReady) {
            Warn "sshd did not become ready within 20s - mount retry may fail"
            $script:pendingFixes += "sshd restart failed - run connect.bat as administrator"
        }
    } elseif (-not $sshdSvc -or $sshdSvc.Status -ne 'Running') {
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

$script:adminFixAttempted = $false

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-LaptopAdminOps {
    param(
        [string]$PubB = '',
        [switch]$FirewallFix,
        [switch]$ForceRestart
    )
    if (Test-IsAdmin) {
        if ($PubB) { Install-ServerKey $PubB -ForceRestart:$ForceRestart }
        if ($FirewallFix) {
            $fw = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
            if (-not $fw) {
                New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
                    -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                    -ErrorAction SilentlyContinue | Out-Null
            } else {
                Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any -ErrorAction SilentlyContinue
            }
        }
        $script:adminFixAttempted = $true
        return $true
    }
    Write-Host ''
    Write-Host '    Administrator access is required to fix laptop SSH.' -ForegroundColor Yellow
    $yn = (Read-Host '    Allow administrator access? [Y/n]').Trim()
    if ($yn -match '^[Nn]') { return $false }
    @(
        "PUB=$PubB",
        "LAPTOP_USER=$($script:LaptopUser)",
        "FIREWALL=$(if ($FirewallFix) { '1' } else { '0' })",
        "FORCE_RESTART=$(if ($ForceRestart) { '1' } else { '0' })"
    ) | Set-Content -Path (Join-Path $CfgDir 'adminfix.pending') -Encoding ASCII
    $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-AdminFix')
    $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs -Wait -PassThru
    $script:adminFixAttempted = $true
    return ($proc.ExitCode -eq 0)
}

function Test-AuthorizedKeyFragment {
    param(
        [string]$Path,
        [string]$PubFragment
    )
    if (-not $PubFragment -or -not (Test-Path $Path)) { return $false }
    $pattern = [regex]::Escape($PubFragment)
    return [bool](Select-String -Path $Path -Pattern $pattern -Quiet -ErrorAction SilentlyContinue)
}

function Test-LaptopSshReady {
    param([string]$PubFragment = '')
    $reasons = [System.Collections.Generic.List[string]]::new()
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') { $reasons.Add('OpenSSH Server (sshd) is not running') }
    try {
        $fw = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction Stop
        if ($fw.Enabled.ToString() -ne 'True') { $reasons.Add('SSH firewall rule disabled') }
    } catch {
        if (-not (Test-IsAdmin)) { $reasons.Add('Cannot verify SSH firewall rule (need administrator)') }
    }
    if ($PubFragment) {
        $userAk = Join-Path $SshDir 'authorized_keys'
        $adminAk = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
        $hasKey = (Test-AuthorizedKeyFragment -Path $userAk -PubFragment $PubFragment) `
               -or (Test-AuthorizedKeyFragment -Path $adminAk -PubFragment $PubFragment)
        if (-not $hasKey) { $reasons.Add('Server laptop key not in authorized_keys') }
    }
    return [PSCustomObject]@{ Ready = ($reasons.Count -eq 0); Reasons = @($reasons) }
}

function Ensure-LaptopSshReady {
    param([string]$PubB = '')
    $frag = if ($PubB) { ($PubB -split '\s+')[1] } else { '' }
    $check = Test-LaptopSshReady -PubFragment $frag
    if ($check.Ready) { return $true }
    Write-Host ''
    foreach ($r in $check.Reasons) { Warn $r }
    return (Invoke-LaptopAdminOps -PubB $PubB -FirewallFix -ForceRestart)
}

if ($script:RunAdminFix) {
    $_cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
    if (Test-Path $_cfg) {
        $conf = @{}; Get-Content $_cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $conf[$matches[1]] = $matches[2] } }
        if ($conf.LAPTOP_USER -and (Test-Path "C:\Users\$($conf.LAPTOP_USER)")) {
            $CfgDir = Join-Path "C:\Users\$($conf.LAPTOP_USER)" '.config\claude-connect'
        }
    }
    $fixFile = Join-Path $CfgDir 'adminfix.pending'
    if (-not (Test-Path $fixFile)) { Write-Host '[X] No admin fix pending' -ForegroundColor Red; exit 1 }
    $fixLines = @{}; Get-Content $fixFile | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $fixLines[$matches[1]] = $matches[2] } }
    Remove-Item $fixFile -Force -ErrorAction SilentlyContinue
    if ($fixLines.LAPTOP_USER) { $SshDir = Join-Path "C:\Users\$($fixLines.LAPTOP_USER)" '.ssh' }
    $pub = $fixLines.PUB
    if ($pub) { Install-ServerKey $pub -ForceRestart:($fixLines.FORCE_RESTART -eq '1') }
    if ($fixLines.FIREWALL -eq '1') {
        $fw = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
        if (-not $fw) {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
                -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                -ErrorAction SilentlyContinue | Out-Null
        } else {
            Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

function Initialize-ServerSession {
    param(
        [Parameter(Mandatory)][string]$ConnectScriptDir,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$SshCfgPath
    )
    $initOut = (SshX "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub") -join "`n"
    $lines = ($initOut -replace "`r",'') -split "`n" | Where-Object { $_.Trim() -ne '' }
    $uidStr = [string]($lines | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1) -replace '\D',''
    $script:Port = 20000 + [int]$uidStr
    $pubB = ($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1).Trim()
    if ($script:Port -le 20000 -or $script:Port -gt 65535) {
        return @{ Ok = $false; Error = 'could not get UID from server'; PubB = '' }
    }
    if (-not $pubB) {
        return @{ Ok = $false; Error = 'could not read server key'; PubB = '' }
    }

    $scpProcs = @()
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if ($dir) {
        foreach ($pair in @(
            @{ File = 'claude-mount.sh'; Dest = 'claude-mount' },
            @{ File = 'claude-git-setup.sh'; Dest = 'claude-git-setup' }
        )) {
            $src = [System.IO.Path]::Combine($dir, $pair.File)
            if (Test-Path $src) {
                $scpProcs += Start-Process -FilePath 'scp' -PassThru -NoNewWindow `
                    -ArgumentList @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=30', '-q', $src, "${Alias}:~/.local/bin/$($pair.Dest)")
            }
        }
    }

    Install-ServerKey $pubB -UserOnly

    Remove-SshHostBlock $SshCfgPath $Alias
    @"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    RemoteForward $Port localhost:22
    ExitOnForwardFailure no
"@ | Add-Content -Path $SshCfgPath -Encoding ASCII
    Repair-SshPerm $SshCfgPath "SSH config"
    Push-ServerConnectConf

    $pushOk = $true
    foreach ($proc in $scpProcs) {
        try {
            Wait-Process -Id $proc.Id -ErrorAction Stop
            if ($proc.ExitCode -ne 0) {
                $pushOk = $false
                $script:pendingFixes += 'server script push failed'
            }
        } catch {
            $pushOk = $false
            $script:pendingFixes += 'server script push failed'
        }
    }
    if ($dir -and $scpProcs.Count -gt 0) {
        $chmodCmd = @()
        if (Test-Path ([System.IO.Path]::Combine($dir, 'claude-mount.sh'))) {
            $chmodCmd += "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc"
        }
        if (Test-Path ([System.IO.Path]::Combine($dir, 'claude-git-setup.sh'))) {
            $chmodCmd += 'chmod +x ~/.local/bin/claude-git-setup'
        }
        if ($chmodCmd.Count -gt 0) { SshX ($chmodCmd -join '; ') 2>$null | Out-Null }
    }

    return @{ Ok = $pushOk; PubB = $pubB; Error = '' }
}

function SshX([string]$Cmd) {
    # ConnectTimeout=30: handles slow VPN/internet (was 10, too short)
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $Alias $Cmd
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

function Get-ActiveMountId {
    $line = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null") -join '').Trim()
    if ($line -match 'ACTIVE_MOUNT=(.*)$') { return $matches[1].Trim() }
    return ''
}

function Get-Mounts {
    $activeId = Get-ActiveMountId
    $out = @()
    foreach ($line in ((SshX "$CM list 2`>/dev/null") -split "`n")) {
        if ($line.Trim() -match '^([^\|]+)\|([^\|]*)\|([^\|]*)\|([^\|]+)$') {
            $id = $matches[1].Trim()
            $out += [PSCustomObject]@{
                Id     = $id
                Label  = $matches[2].Trim()
                Rpath  = $matches[3].Trim()
                Lpath  = $matches[4].Trim()
                Path   = $matches[4].Trim()
                Active = ($id -eq $activeId)
            }
        }
    }
    return $out
}

function Select-Mount($mounts, $n) {
    if ($n -match '^[0-9]+$') {
        $i = [int]$n - 1
        if ($i -ge 0 -and $i -lt $mounts.Count) { return $mounts[$i] }
    }
    return $null
}

function Add-Project {
    Write-Host ''
    Write-Host '    Add project' -ForegroundColor White
    Write-Host ''
    $picked = Pick-LaptopFolder
    if ($picked) {
        Write-Host "    Selected: $picked" -ForegroundColor DarkGray
        $nPath = $picked
    } else {
        $nPath = (Read-Host '    Folder on your laptop (e.g. D:\Smart)').Trim() -replace '\\','/'
    }
    if (-not $nPath) { Warn 'Path is required.'; return $null }
    if ($nPath -match '^[A-Za-z]:$') { $nPath = "$nPath/" }
    $idSrc = $nPath -replace '/+$',''
    $nId   = (($idSrc -split '/')[-1]).ToLower() -replace '[^a-z0-9_-]','-' -replace '-+','-' -replace '^-|-$',''
    $nLbl  = if ($nId) { (Get-Culture).TextInfo.ToTitleCase(($nId -replace '-',' ')) } else { "" }
    $d = (Read-Host "    Name [$nLbl]").Trim(); if ($d) { $nLbl = $d }
    if (-not $nId) { $nId = $nLbl.ToLower() -replace '[^a-z0-9_-]','-' -replace '-+','-' -replace '^-|-$','' }
    if (-not $nId) { Warn "Could not derive a project name."; return $null }
    $nLpath = "/home/$RemoteUser/mounts/$nId"
    Write-Host ""
    $nLbl_sh  = $nLbl  -replace "'", "'\\''"; $nPath_sh = $nPath -replace "'", "'\\''";
    $out = (SshX "$CM add '$nId' '$nLbl_sh' '$nPath_sh' '$nLpath'" 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { Warn $out.Trim(); return $null }
    return ,([PSCustomObject]@{ Id = $nId; Path = $nLpath })
}

function Choose-Project {
    param([array]$Mounts)

    $mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $Mounts)
    $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $Mounts
    while ($true) {
        if ($mounts.Count -eq 0) {
            if ($hiddenCount -gt 0) {
                Write-Host "    No PC projects ($hiddenCount Mac-only on server)." -ForegroundColor DarkGray
                Write-Host ''
            }
            $null = ($added = Add-Project)
            if (-not $added) { return $null }
            return ,$added
        }

        Write-GitModeBanner -GitMode (Get-GitMode)
        Write-ProjectTable -Mounts $mounts
        $c = (Read-Host '    >').Trim().ToLower()
        Write-Host ''
        if (-not $c) { continue }
        if ($c -match '^[0-9]+$') {
            $null = ($m = Select-Mount $mounts $c)
            if (-not $m) { Warn "Not found."; continue }
            if (-not (Warn-InvalidProjectRpath -Rpath $m.Rpath -Num $c -Os 'windows')) { continue }
            return ,([PSCustomObject]@{ Id = $m.Id; Path = $m.Path })
        }

        switch ($c) {
            "a" {
                $null = ($r = Add-Project)
                if ($r) { return ,$r }
                $null = ($allMounts = @(Get-Mounts))
                $null = ($mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $allMounts))
                $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $allMounts
            }
            'e' {
                $null = ($cur = Select-Mount $mounts (Read-Host '    Edit number').Trim())
                if (-not $cur) { Warn 'Not found.'; continue }
                Write-Host ''
                $nLbl = (Read-Host "    Display name [$($cur.Label)]").Trim(); if (-not $nLbl) { $nLbl = $cur.Label }
                $nR   = (Read-Host "    Laptop folder [$($cur.Rpath)]").Trim() -replace '\\','/'; if (-not $nR) { $nR = $cur.Rpath }
                Write-Host "    Server path (read-only): $($cur.Lpath)" -ForegroundColor DarkGray
                $nL   = $cur.Lpath
                $nLbl_sh = $nLbl -replace "'", "'\\''"; $nR_sh = $nR -replace "'", "'\\''"
                $editOut = (SshX "$CM edit '$($cur.Id)' '$nLbl_sh' '$nR_sh' '$nL'" 2>&1) | Out-String
                if ($LASTEXITCODE -ne 0) { Warn $editOut.Trim() }
                $null = ($allMounts = @(Get-Mounts))
                $null = ($mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $allMounts))
                $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $allMounts
            }
            "d" {
                $null = ($m = Select-Mount $mounts (Read-Host "    Delete number").Trim())
                if (-not $m) { Warn "Not found."; continue }
                if ((Read-Host "    Delete '$($m.Label)'? [y/N]").Trim().ToLower() -eq "y") {
                    $rmOut = (SshX "$CM rm '$($m.Id)'" 2>&1) | Out-String
                    if ($LASTEXITCODE -ne 0) { Warn $rmOut.Trim() }
                    $null = ($allMounts = @(Get-Mounts))
                    $null = ($mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $allMounts))
                    $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $allMounts
                }
            }
            'c' {
                Write-Host ''
                Write-Host '    Configuration' -ForegroundColor White
                Write-Host ''
                Write-Host "    Username   : $RemoteUser" -ForegroundColor DarkGray
                Write-Host "    Git mode   : $(Get-GitModeLabel) ($(Get-GitMode))" -ForegroundColor DarkGray
                Write-Host "    IDE        : $(Get-EditorPref -CfgDir $CfgDir)" -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '    1  Change server username' -ForegroundColor DarkGray
                Write-Host '    2  Change IDE preference' -ForegroundColor DarkGray
                Write-Host '    3  Change git mode' -ForegroundColor DarkGray
                Write-Host ''
                $cfgChoice = (Read-Host '    >').Trim()
                switch ($cfgChoice) {
                    '1' {
                        $nUser = (Read-Host '    New server username (Enter to cancel)').Trim()
                        if ($nUser -and $nUser -ne $RemoteUser) {
                            @("REMOTE_USER=$nUser", "LAPTOP_USER=$env:USERNAME") | Set-Content -Path $Cfg -Encoding ASCII
                            Remove-SshHostBlock $sshCfg $Alias
                            Write-Host ''; Write-Host '    Saved. Re-run connect.bat.' -ForegroundColor Green
                            Write-Host ''; exit 0
                        }
                    }
                    '2' { Configure-EditorPref -CfgDir $CfgDir }
                    '3' { Configure-GitMode }
                    default { Write-Host '    Cancelled.' -ForegroundColor DarkGray; Write-Host '' }
                }
            }
            "g" { Configure-GitMode }
            "q" { Write-Host ""; exit 0 }
            default { Warn "Enter a number or a/e/d/c/g/q." }
        }
    }
}

# config
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
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
$script:LaptopUser = $LaptopUser
# When elevated as a different admin account, $env:USERPROFILE may point to the wrong user profile.
# Use LAPTOP_USER from config for .ssh and editor prefs (same as SSH key paths).
if ($LaptopUser -and (Test-Path "C:\Users\$LaptopUser")) {
    $CfgDir = [System.IO.Path]::Combine("C:\Users\$LaptopUser", '.config', 'claude-connect')
    $Cfg    = [System.IO.Path]::Combine($CfgDir, 'connect.conf')
    $SshDir = [System.IO.Path]::Combine("C:\Users\$LaptopUser", '.ssh')
}
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
New-Item -ItemType Directory -Force -Path $SshDir  | Out-Null

Clear-Host
Write-ConnectHeader -Alias $Alias -ServerIP $ServerIP -Version $script:ConnectVersion
Set-ConnectTitle 'Claude Connect'
Write-BootstrapHint -CfgDir $CfgDir
Write-Host ''

# Fix .ssh dir permissions (after LAPTOP_USER rebind when elevated)
$_dirOut = (icacls $SshDir 2>$null) -join ' '
$_dirFixed = $_dirOut -match '\(I\)|Everyone|BUILTIN\\Users'
icacls $SshDir /reset 2>$null | Out-Null
icacls $SshDir /inheritance:r /grant "$env:USERNAME`:(OI)(CI)F" 2>$null | Out-Null
if ($LaptopUser -and $LaptopUser -ne $env:USERNAME) {
    icacls $SshDir /grant "$($LaptopUser):(OI)(CI)F" 2>$null | Out-Null
}
if ($_dirFixed) { Write-Host "      -> fixed: .ssh directory permissions" -ForegroundColor DarkGray; Write-Host "" }

# SSH key
Step "Laptop SSH key"
$keyA = [System.IO.Path]::Combine($SshDir, 'id_ed25519')
if (-not (Test-Path $keyA)) { ssh-keygen -t ed25519 -N '""' -f $keyA -q }
if (Test-Path $keyA) {
    Repair-SshPerm $keyA "SSH private key"
    StepOk
} else { StepFail "could not create key"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }

# SSH config
$sshCfg = [System.IO.Path]::Combine($SshDir, 'config')
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
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
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
    # Clear stale known_hosts entry so host key mismatch doesn't block auth
    ssh-keygen -R $ServerIP 2>$null | Out-Null
    Write-Host "    Enter server password (one time only):" -ForegroundColor Yellow
    $pubKeyContent = (Get-Content "$keyA.pub").Trim() -replace "'", "'\''"
    ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $keyCopyOk = ($LASTEXITCODE -eq 0)
    Step "Verifying connection"
    $verifySW = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
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

# Server setup (port + key + scripts in one step; script push runs parallel to local key install)
Step "Server setup"
$boot = Initialize-ServerSession -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias -SshCfgPath $sshCfg
if ($boot.Error) { StepFail $boot.Error; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
if (-not $boot.Ok) { StepFail ($script:pendingFixes -join ', ') }
else { StepOk "port $Port git=$(Get-GitMode)" }
$PubB = $boot.PubB

Write-Host ''
Write-Host '    Ready' -ForegroundColor Green
Write-Host ''
Mark-BootstrapDone -CfgDir $CfgDir
$null = Ensure-LaptopSshReady -PubB $PubB
$script:LaptopSshVerified = $false

$exitRequested = $false
:menuLoop while (-not $exitRequested) {
    Step "Loading projects"
    $null = ($allMounts = @(Get-Mounts))
    StepOk (Get-MountListStepLabel -Os 'windows' -Mounts $allMounts)
    $go = @(Choose-Project -Mounts $allMounts)[-1]
    if (-not $go) { break }

    if ($Ide) {
        $EditorCmd = if ($Ide -eq 'code' -or $Ide -eq 'vscode') { 'code' } else { 'cursor' }
        $EditorName = if ($EditorCmd -eq 'code') { 'VS Code' } else { 'Cursor' }
        Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'editor.conf')) -Value $EditorCmd -Encoding ASCII | Out-Null
        Ensure-EditorOnPath $EditorCmd | Out-Null
    } else {
        $editorChoice = @(Resolve-EditorChoice -CfgDir $CfgDir)[-1]
        if (-not $editorChoice) {
            Warn 'No editor found. Install Cursor or VS Code (+ Remote-SSH extension), then re-run.'
            Write-Host ''; Read-Host '    Press Enter to close' | Out-Null; exit 1
        }
        $EditorCmd = $editorChoice.EditorCmd
        $EditorName = $editorChoice.EditorName
    }

    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${Port}:localhost:22" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Step "Checking SSH service"
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc) {
        StepFail "OpenSSH Server not installed"
        Write-Host ""
        Write-Host "    OpenSSH Server not found - installing now..." -ForegroundColor Yellow
        $installed = $false
        # Method 1: Windows Capability (Win10/11 built-in) - requires Windows Update service
        $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
        if ($wuSvc -and $wuSvc.Status -ne 'Running') {
            Write-Host "    Starting Windows Update service for install..." -ForegroundColor DarkGray
            Start-Service wuauserv -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
            Write-Host "    OpenSSH Server installed ok (via Windows Capability)." -ForegroundColor Green
            $installed = $true
        } catch {
            Write-Host "    Windows Capability install failed: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
        # Method 2: winget fallback
        if (-not $installed) {
            Write-Host "    Trying winget fallback..." -ForegroundColor DarkGray
            try {
                $wg = Get-Command winget -ErrorAction Stop
                & winget install --id Microsoft.OpenSSH.Beta -e --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
                $svc = Get-Service sshd -ErrorAction SilentlyContinue
                if ($svc) {
                    Write-Host "    OpenSSH Server installed ok (via winget)." -ForegroundColor Green
                    $installed = $true
                }
            } catch {
                Write-Host "    winget fallback failed: $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        }
        if (-not $installed) {
            Write-Host "    Could not auto-install OpenSSH Server." -ForegroundColor Red
            Write-Host "    Manual fix: Settings -> Apps -> Optional Features -> OpenSSH Server" -ForegroundColor DarkGray
            Write-Host "    Or run as admin: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" -ForegroundColor DarkGray
            Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
        }
        Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') {
            Write-Host "    Could not start sshd after install. Run as admin: Start-Service sshd" -ForegroundColor Red
            Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
        }
        Write-Host "    sshd started ok." -ForegroundColor Green
        # Re-run key setup: ProgramData\ssh\ now exists after install, first call skipped it.
        # ForceRestart=$true so sshd picks up administrators_authorized_keys (only re-read on start).
        if ($PubB) { $null = Invoke-LaptopAdminOps -PubB $PubB -ForceRestart }
    } elseif ($svc.Status -ne 'Running') {
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
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
            -ErrorAction SilentlyContinue | Out-Null
    } elseif ($fwRule.Enabled.ToString() -ne 'True' -or $fwRule.Profile.ToString() -notmatch 'Any') {
        Write-Host "    [!] Firewall rule for SSH needs update - fixing..." -ForegroundColor Yellow
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Profile Any -ErrorAction SilentlyContinue
    }

    $editorOpened = $false
    $script:CursorAuthNeedsBootstrap = $false

    :mainLoop while ($true) {
    $alreadyDown  = $false
    $bgTunnel     = $null

    try {
        :sessionLoop while ($true) {
            $tunnelReused = $false
            if (-not (Ensure-SessionTunnel -Alias $Alias -BgTunnel ([ref]$bgTunnel) -TunnelReused ([ref]$tunnelReused))) {
                Step 'Starting SSH tunnel'
                StepFail "did not come up on port $Port"
                Write-Host ""
                Warn "Tunnel did not come up on port $Port"
                if (-not (PortOpen $ServerIP 22)) {
                    Warn "Server unreachable - VPN disconnected?"
                } else {
                    Warn "Check Windows Firewall - port 22 must allow inbound connections"
                }
                Write-Host ""
                Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
                $rk = Read-RetryQuitKey
                if ($rk -eq 'r') { Write-Host ""; continue }
                Push-ServerConnectConf -ActiveMount ''
                $alreadyDown = $true; break sessionLoop
            }
            if (-not $tunnelReused) {
                # Wait-ForTunnelUp already printed progress lines
            } elseif ($tunnelReused) {
                Step 'SSH tunnel'
                StepOk "reusing pid $($bgTunnel.Id)"
            }

            $mountSrc = Get-ClaudeMountSrc -ConnectScriptDir $script:ConnectScriptDir
            Prepare-ServerSessionParallel -ProjectId $go.Id -MountSrc $mountSrc -Alias $Alias

            Invoke-RecoverIfNeeded -ProjectId $go.Id -FreshTunnel:(-not $tunnelReused)

            if (-not (Test-TunnelUp)) {
                Write-Host "      -> tunnel dropped during recover, restarting..." -ForegroundColor DarkGray
                $script:LaptopSshVerified = $false
                continue
            }

            Step 'Verifying laptop SSH key'
            if (Ensure-LaptopReverseSshCached -PubB $PubB) {
                StepOk
            } else {
                StepFail 'server cannot authenticate to this PC'
                Write-Host ''
                Write-Host '    R = retry   Q = quit' -ForegroundColor DarkGray
                $rk = Read-RetryQuitKey
                if ($rk -eq 'r') { Write-Host ''; continue }
                Push-ServerConnectConf -ActiveMount ''
                $alreadyDown = $true; break sessionLoop
            }

            Step "Mounting files"
            $mountSW = [System.Diagnostics.Stopwatch]::StartNew()
            $mountResult = Invoke-MountProject -ProjectId $go.Id -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias -TrustedTunnel
            $mountOut = $mountResult.Out
            $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
            $mountOk  = $mountResult.Ok

            if (-not $mountOk -and $mountOut -match 'key auth failed|connection reset|reset by peer|publickey|Permission denied') {
                Write-Host ' retrying...' -ForegroundColor DarkGray
                Write-Host "      -> $($mountOut.Trim())" -ForegroundColor DarkGray
                if ($mountOut -match 'connection reset|reset by peer') {
                    Warn 'Connection reset - killing stale mounts, fixing firewall, restarting sshd'
                    SshX 'pkill -u "$USER" sshfs 2>/dev/null; true' 2>$null | Out-Null
                    $null = Invoke-LaptopAdminOps -PubB '' -FirewallFix -ForceRestart:$false
                } else {
                    Warn 'Key rejected - reinstalling server key and restarting sshd'
                }
                $newPub = ((SshX 'cat ~/.ssh/claude_laptop.pub') -join '').Trim()
                if (-not $newPub) { Warn 'Could not fetch server public key - skipping key reinstall' }
                if ($newPub) {
                    $null = Invoke-LaptopAdminOps -PubB $newPub -ForceRestart
                    Write-Host '      -> waiting for sshd to stabilize...' -ForegroundColor DarkGray
                    Start-Sleep -Seconds 2
                    if (-not (Test-Tunnel)) {
                        Write-Host ''; Warn 'Tunnel dropped after sshd restart - reconnecting...'
                        continue
                    }
                    Write-Host '      -> tunnel: alive' -ForegroundColor DarkGray
                    Step 'Mounting files'
                    $mountSW = [System.Diagnostics.Stopwatch]::StartNew()
                    $mountResult = Invoke-MountProject -ProjectId $go.Id -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias -TrustedTunnel
                    $mountOut = $mountResult.Out
                    $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
                    $mountOk  = $mountResult.Ok
                }
            }

            if (-not $mountOk) {
                if ($script:adminFixAttempted) {
                    Warn ('Auto-fix exhausted: {0} - try e edit path, then R' -f $mountOut.Trim())
                }
                StepFail $mountOut.Trim()
                if ($mountOut -match 'No such file|not found|cannot find') {
                    Warn "Path not found on laptop. Use 'e edit' to correct the project path."
                }
                Write-Host ""
                Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
                $rk = Read-RetryQuitKey
                if ($rk -eq 'r') { Write-Host ""; continue }
                Push-ServerConnectConf -ActiveMount ''
                $alreadyDown = $true; break sessionLoop
            }

            StepOk "${mountT}s"
            Show-MountGitWarn $mountOut
            $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '')
            if ($cleanOut -and $cleanOut -notmatch '^warn:') { Write-Host "      -> mounted: $cleanOut" -ForegroundColor Green }

            $script:ActiveProjectId = $go.Id

            $script:CursorAuthNeedsBootstrap = $false
            if ($EditorCmd -eq 'cursor' -and (Get-Command Sync-CursorGoldenAuth -ErrorAction SilentlyContinue)) {
                $gsPath = Join-Path (Get-LocalCursorGlobalStorage) 'state.vscdb'
                $cursorRunning = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path).Count -gt 0
                Step "Syncing Cursor auth"
                if ($cursorRunning -and (Test-LocalCursorAuthComplete -DbPath $gsPath)) {
                    StepOk 'skipped (editor open)'
                } else {
                    $authSync = Sync-CursorGoldenAuth -Alias $Alias
                    if ($authSync.Skipped) {
                        if ($authSync.AlreadyComplete) { StepOk 'already ok' }
                        else { StepOk 'skipped' }
                    }
                    elseif ($authSync.Ok) {
                        StepOk
                        Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'cursor-auth.ok')) -Value (Get-Date -Format 'o') -Encoding ASCII | Out-Null
                    }
                    elseif ($authSync.TokensOnly) {
                        StepOk 'tokens only'
                        $script:CursorAuthNeedsBootstrap = $true
                        Warn 'Chat needs server account profile - sign in inside [Claude Server] only, then press P'
                    }
                    else {
                        StepFail 'could not merge server auth'
                        $script:CursorAuthNeedsBootstrap = $true
                        Warn 'Sign in to SERVER account in [Claude Server] window - personal Cursor is never touched'
                    }
                }
                if (-not $cursorRunning -and (Get-Command Repair-CursorComposerWorkspaceBindings -ErrorAction SilentlyContinue)) {
                    $null = Repair-CursorComposerWorkspaceBindings -Alias $Alias -RemotePath $go.Path
                }
            }

            if (-not $editorOpened) {
                Step "Opening $EditorName"
                if (-not (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)) {
                    StepFail "$EditorName not found (install Cursor or VS Code + Remote-SSH)"
                } else {
                    StepOk $($go.Path)
                    $editorOpened = $true
                    if ($EditorCmd -eq 'cursor') {
                        Write-Host '      -> Server profile [Claude Server] - personal Cursor is separate' -ForegroundColor DarkGray
                    }
                }
                Write-Host ""
                Write-Host "    Run 'claude' in the $EditorName terminal." -ForegroundColor DarkGray
            }

            $sessionExtras = @()
            if ($script:CursorAuthNeedsBootstrap) {
                $sessionExtras += 'P = push server login to golden (after sign-in in [Claude Server] only)'
            }
            Write-SessionBox -ExtraLines $sessionExtras
            Set-ConnectTitle ('Claude Connect | {0} | {1}' -f $go.Id, (Get-GitModeLabel))

            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

            $action = 'q'
            $gotKey = $false
            $lastStatusAt = [DateTime]::MinValue
            $script:lastToastAt = $null
            while (-not $bgTunnel.HasExited) {
                if ($editorOpened -and $EditorCmd -eq 'cursor') {
                    $editorOpened = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path).Count -gt 0
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk $true -EditorOpen $editorOpened -EditorName $EditorName
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    elseif ($script:CursorAuthNeedsBootstrap -and (
                        $ki.KeyChar.ToString().ToLower() -eq 'p' -or $ki.Key -eq [ConsoleKey]::P)) { $action = 'p' }
                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 200
            }
            if (-not $gotKey -and $bgTunnel.HasExited) {
                if (-not $script:lastToastAt -or ((Get-Date) - $script:lastToastAt).TotalSeconds -gt 60) {
                    Set-ConnectTitle 'Claude Connect - reconnecting...'
                    Show-ConnectToast 'Tunnel dropped - reconnecting...'
                    $script:lastToastAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'q' -or $ki.Key -eq [ConsoleKey]::Q -or
                        $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                } else {
                    $action = 'r'
                    Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
                }
            }

            if ($action -eq 'g') {
                Configure-GitMode
                continue sessionLoop
            }

            if ($action -eq 'o') {
                if (-not $editorOpened) {
                    Write-Host ''
                    Step "Reopening $EditorName"
                    if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                        StepOk $go.Path
                        $editorOpened = $true
                    } else {
                        StepFail "$EditorName not found"
                    }
                    Write-Host ''
                }
                continue sessionLoop
            }

            if ($action -eq 'p') {
                if (Get-Command Push-CursorGoldenFromServerProfile -ErrorAction SilentlyContinue) {
                    Write-Host ''
                    Write-Host '    Pushing golden from [Claude Server] profile...' -ForegroundColor Cyan
                    $push = Push-CursorGoldenFromServerProfile -Alias $Alias
                    if ($push.Ok) {
                        Write-Host "    $($push.Message)" -ForegroundColor Green
                        $script:CursorAuthNeedsBootstrap = $false
                    } else {
                        Write-Host "    $($push.Message)" -ForegroundColor Yellow
                    }
                    Write-Host ''
                }
                continue sessionLoop
            }

            if ($action -eq 'r') {
                if ($gotKey) {
                    $alreadyDown = $false
                    Write-Host ''
                    Write-Host '    Reconnecting...' -ForegroundColor Cyan
                    Write-Host ''
                    continue sessionLoop
                }
                Write-Host '    Connection dropped - recovering...' -ForegroundColor Yellow
                Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop
                if ($bgTunnel -and -not $bgTunnel.HasExited) {
                    Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
                }
                $bgTunnel = $null
                $alreadyDown = $true
                $script:LaptopSshVerified = $false
                Write-Host ''
                continue sessionLoop
            }

            # Disconnect (Q)
            Write-Host ""
            Write-Host "    Disconnecting..." -ForegroundColor DarkGray
            Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            if ($bgTunnel -and -not $bgTunnel.HasExited) {
                Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
            }
            $alreadyDown = $true
            Write-Host "    Laptop folder restored." -ForegroundColor Green
            break sessionLoop
        }
    } finally {
        # Runs on window close (CTRL_CLOSE_EVENT) - ensure cleanup even if window is force-closed
        if (-not $alreadyDown) {
            Write-Host ""
            Write-Host "    Disconnecting..." -ForegroundColor DarkGray
            Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            Write-Host "    Laptop folder restored." -ForegroundColor Green
            Write-Host ""
        }
        # Always kill tunnel - even if $alreadyDown (e.g. tunnel-fail or mount-fail Q path)
        if ($bgTunnel -and -not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
        }
    }

    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

    $postKey = Read-PostDisconnectKey -DefaultChar M -TimeoutSec 10
    switch ($postKey) {
        'm' {
            Write-Host '    Back to project menu...' -ForegroundColor Green
            $editorOpened = $false
            Start-Sleep -Seconds 1
            Write-Host ''
            break mainLoop
        }
        'c' {
            Write-Host '    Reconnecting...' -ForegroundColor Green
            $editorOpened = $false
            Start-Sleep -Seconds 1
            Write-Host ''
            continue mainLoop
        }
        default {
            Write-Host '    Exiting...' -ForegroundColor DarkGray
            $exitRequested = $true
            break mainLoop
        }
    }

    } # end :mainLoop
} # end :menuLoop
Write-Host ''
