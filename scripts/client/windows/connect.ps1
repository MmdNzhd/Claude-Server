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

# Always run elevated (sshd, firewall, administrators_authorized_keys need admin).
if (-not $AdminFix) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($Setup) { $elevArgs += '-Setup' }
        if ($Ide) { $elevArgs += '-Ide'; $elevArgs += $Ide }
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs -ErrorAction Stop | Out-Null
        } catch {
            Write-Host ''
            Write-Host '  [X] Administrator approval is required to run Claude Connect.' -ForegroundColor Red
            Write-Host ''; Read-Host '    Press Enter to close' | Out-Null
            exit 1
        }
        exit 0
    }
}

trap {
    Write-Host ''
    Write-Host "  [X] Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkGray
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "UNHANDLED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
    Write-Host ''
    Read-Host '    Press Enter to close' | Out-Null
    exit 1
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
    Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}
$ServerIP = "192.168.210.240"
$Alias    = "claude-server"
$script:ConnectVersion = '20260715.15'
$CfgDir   = Join-Path $env:USERPROFILE ".config\claude-connect"
$Cfg      = Join-Path $CfgDir "connect.conf"
$SshDir   = Join-Path $env:USERPROFILE ".ssh"
$CM       = '$HOME/.local/bin/claude-mount'

function Die($m) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "ERROR: $m" 'ERROR'
        Close-ConnectLog
    }
    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}
function Warn($m) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog "WARN: $m" 'WARN' }
    Write-Host "  [!] $m" -ForegroundColor DarkYellow
}
function Step($m) {
    $script:currentStepName = $m
    $script:currentStepStartedAt = Get-Date
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "STEP begin: $m"
    }
    Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan
}
function StepOk  {
    param([string]$d='')
    $ms = 0
    if ($script:currentStepStartedAt) {
        $ms = [int]((Get-Date) - $script:currentStepStartedAt).TotalMilliseconds
    }
    if ($script:ConnectPerf -and $script:currentStepName) {
        switch -Regex ($script:currentStepName) {
            'Mounting files' { $script:ConnectPerf.MountMs = $ms }
            'Syncing Cursor auth' { $script:ConnectPerf.AuthMs = $ms }
            'Opening' { $script:ConnectPerf.OpenMs = $ms }
        }
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $detail = if ($d) { $d } else { 'ok' }
        Write-ConnectLog "STEP end: $($script:currentStepName) ok ms=$ms detail=$detail"
    }
    if ($d) { Write-Host " $d" -ForegroundColor Green } else { Write-Host " ok" -ForegroundColor Green }
    foreach ($fx in $script:pendingFixes) { Write-Host "      -> fixed: $fx" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
    $script:currentStepStartedAt = $null
}
function StepFail {
    param([string]$d='')
    $ms = 0
    if ($script:currentStepStartedAt) {
        $ms = [int]((Get-Date) - $script:currentStepStartedAt).TotalMilliseconds
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $detail = if ($d) { $d } else { 'failed' }
        Write-ConnectLog "STEP end: $($script:currentStepName) failed ms=$ms detail=$detail" 'WARN'
    }
    Write-Host " failed" -ForegroundColor Red
    if ($d) { Write-Host "      -> $d" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
    $script:currentStepStartedAt = $null
}
$script:pendingFixes = @()
$script:currentStepName = ''
$script:currentStepStartedAt = $null

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
Show-ConnectConsoleIfHidden

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

$_connectDiag = Dot-SourceSibling 'connect-diagnostic.ps1'
if (-not $_connectDiag) {
    $_connectDiag = Join-Path $script:ConnectScriptDir 'connect-diagnostic.ps1'
    if (-not (Test-Path $_connectDiag)) {
        $_connectDiag = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'connect-diagnostic.ps1'
    }
}
if (Test-Path $_connectDiag) { . $_connectDiag }

$_connectUi = Dot-SourceSibling 'connect-ui.ps1'
if (-not $_connectUi) { Die 'connect-ui.ps1 not found - re-copy the full windows package' }
. $_connectUi
Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version $script:ConnectVersion
$script:ConnectPerf = @{
    SshMsTotal = 0
    SshCount   = 0
    MountMs    = 0
    AuthMs     = 0
    OpenMs     = 0
    DiagMs     = 0
}
$script:LaunchPerfFixes = @('F1', 'F2', 'F3', 'F5', 'F4', 'F7')
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Close-ConnectLog }

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
        $restricted = "from=`"127.0.0.1,::1,localhost,::ffff:127.0.0.1`" $pub"
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

function Get-InteractiveLaptopUser {
    if ($script:LaptopUser) { return $script:LaptopUser }
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
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
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_admin_prompt'
    }
    $yn = (Read-Host '    Allow administrator access? [Y/n]').Trim()
    if ($yn -match '^[Nn]') { return $false }
    @(
        "PUB=$PubB",
        "LAPTOP_USER=$($script:LaptopUser)",
        "FIREWALL=$(if ($FirewallFix) { '1' } else { '0' })",
        "FORCE_RESTART=$(if ($ForceRestart) { '1' } else { '0' })"
    ) | Set-Content -Path (Join-Path $CfgDir 'adminfix.pending') -Encoding ASCII
    $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-AdminFix')
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_uac'
    }
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

function Test-WindowsAccountIsLocalAdmin {
    param([string]$UserName = $script:LaptopUser)
    if (-not $UserName) { return $false }
    try {
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
        $groupLabel = ($adminSid.Translate([System.Security.Principal.NTAccount]).Value -split '\\')[-1]
        $members = (& net localgroup $groupLabel 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0) {
            $members = (& net localgroup Administrators 2>$null | Out-String)
        }
        return [bool]($members -match "(?m)^\s*$([regex]::Escape($UserName))\s*$")
    } catch {
        return $false
    }
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
        $adminDir = Split-Path $adminAk
        $userIsAdmin = Test-WindowsAccountIsLocalAdmin
        if ($userIsAdmin -and (Test-Path $adminDir)) {
            if (-not (Test-AuthorizedKeyFragment -Path $adminAk -PubFragment $PubFragment)) {
                $reasons.Add('Server laptop key not in administrators_authorized_keys (Windows admin user)')
            }
        } elseif (-not (Test-AuthorizedKeyFragment -Path $userAk -PubFragment $PubFragment)) {
            $reasons.Add('Server laptop key not in authorized_keys')
        }
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
    if ($fixLines.LAPTOP_USER) {
        $script:LaptopUser = $fixLines.LAPTOP_USER
        $SshDir = Join-Path "C:\Users\$($fixLines.LAPTOP_USER)" '.ssh'
        $CfgDir = Join-Path "C:\Users\$($fixLines.LAPTOP_USER)" '.config\claude-connect'
    }
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
    $pubB = ($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1).Trim()
    if (-not (Acquire-TunnelPort -UidStr $uidStr)) {
        $script:Port = 20000 + [int]$uidStr
        $script:TunnelSlot = 0
    }
    if ($script:Port -le 20000 -or $script:Port -gt 65535) {
        return @{ Ok = $false; Error = 'could not get UID from server'; PubB = '' }
    }
    if (-not $pubB) {
        return @{ Ok = $false; Error = 'could not read server key'; PubB = '' }
    }

    $scpProcs = @()
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if ($dir) {
        SshX 'mkdir -p ~/.local/bin' 2>$null | Out-Null
        $mountSrc = [System.IO.Path]::Combine($dir, 'claude-mount.sh')
        if (Test-Path $mountSrc) {
            $uploadSrc = Get-LfNormalizedShCopy -Src $mountSrc
            $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
            $remoteHash = ((SshX "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}'") -join '').Trim()
            if (-not ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower()))) {
                $scpProcs += Start-Process -FilePath 'scp' -PassThru -NoNewWindow `
                    -ArgumentList @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=30', '-q', $uploadSrc, "${Alias}:~/.local/bin/claude-mount")
            }
        }
        $gitSrc = [System.IO.Path]::Combine($dir, 'claude-git-setup.sh')
        if (Test-Path $gitSrc) {
            $gitLocal = (Get-FileHash -Algorithm SHA256 -Path $gitSrc).Hash
            $gitRemote = ((SshX "sha256sum ~/.local/bin/claude-git-setup 2>/dev/null | awk '{print `$1}'") -join '').Trim()
            if (-not ($gitLocal -and $gitRemote -and ($gitLocal.ToLower() -eq $gitRemote.ToLower()))) {
                $scpProcs += Start-Process -FilePath 'scp' -PassThru -NoNewWindow `
                    -ArgumentList @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=30', '-q', $gitSrc, "${Alias}:~/.local/bin/claude-git-setup")
            }
        }
    }

    Install-ServerKey $pubB
    if (-not (Ensure-LaptopSshReady -PubB $pubB)) {
        return @{ Ok = $false; Error = 'laptop SSH key setup failed'; PubB = $pubB }
    }

    Remove-SshHostBlock $SshCfgPath $Alias
    @"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@ | Add-Content -Path $SshCfgPath -Encoding ASCII
    Sanitize-SshAliasConfig -CfgPath $SshCfgPath -AliasName $Alias
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
            $chmodCmd += "sed -i 's/\r$//' ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc"
        }
        if (Test-Path ([System.IO.Path]::Combine($dir, 'claude-git-setup.sh'))) {
            $chmodCmd += "sed -i 's/\r$//' ~/.local/bin/claude-git-setup 2>/dev/null; chmod +x ~/.local/bin/claude-git-setup"
        }
        if ($chmodCmd.Count -gt 0) { SshX ($chmodCmd -join '; ') 2>$null | Out-Null }
    }

    return @{ Ok = $pushOk; PubB = $pubB; Error = '' }
}

function Escape-BashSingleQuoted([string]$Text) {
    return $Text -replace "'", "'\''"
}

function Add-SshRecentLog([string]$Line) {
    if (-not $script:SshRecentLog) {
        $script:SshRecentLog = [System.Collections.Generic.List[string]]::new()
    }
    $script:SshRecentLog.Add($Line)
    while ($script:SshRecentLog.Count -gt 24) { $script:SshRecentLog.RemoveAt(0) }
}

function Invoke-SshXCore {
    param([Parameter(Mandatory)][string]$RemoteCmd)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = @(& ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 `
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $Alias $RemoteCmd 2>&1)
    $sw.Stop()
    if ($null -eq $lines) { $lines = @() }
    return [PSCustomObject]@{
        Exit = $LASTEXITCODE
        Ms   = [int]$sw.ElapsedMilliseconds
        Out  = ($lines -join "`n")
        Lines = $lines
    }
}

function SshX([string]$Cmd) {
    $origCmd = $Cmd
    $remoteCmd = $Cmd
    if ($remoteCmd -notmatch '^\s*timeout\s') {
        $escaped = Escape-BashSingleQuoted $remoteCmd
        $remoteCmd = "timeout 45 bash -lc '$escaped'"
    }
    $truncCmd = if ($origCmd.Length -gt 200) { $origCmd.Substring(0, 200) + '...' } else { $origCmd }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "SSH_BEGIN cmd=$truncCmd"
    }
    $result = Invoke-SshXCore -RemoteCmd $remoteCmd
    if ($result.Exit -eq 124) {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "SSH_TIMEOUT exit=124 cmd=$truncCmd - retrying once" 'ERROR'
        }
        $result = Invoke-SshXCore -RemoteCmd $remoteCmd
    }
    $truncOut = ($result.Out.Trim() -replace '\s+', ' ')
    if ($truncOut.Length -gt 300) { $truncOut = $truncOut.Substring(0, 300) + '...' }
    if (-not $truncOut) { $truncOut = '(empty)' }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "SSH_END exit=$($result.Exit) ms=$($result.Ms) out=$truncOut"
    }
    if ($script:ConnectPerf) {
        $script:ConnectPerf.SshMsTotal += $result.Ms
        $script:ConnectPerf.SshCount++
    }
    Add-SshRecentLog "exit=$($result.Exit) ms=$($result.Ms) cmd=$truncCmd"
    if ($result.Exit -ne 0 -and $result.Exit -ne 124) {
        $script:LastSshExit = $result.Exit
    }
    $global:LASTEXITCODE = $result.Exit
    return $result.Lines
}

function Begin-ConnectRecovery {
    param(
        [Parameter(Mandatory)][ValidateSet('manual', 'auto')][string]$Trigger,
        [Parameter(Mandatory)][string]$ProjectId,
        [bool]$EditorWasOpen
    )
    $script:RecoveryGeneration++
    $script:RecoveryStartedAt = Get-Date
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "RECOVERY_BEGIN trigger=$Trigger project=$ProjectId editor_opened=$EditorWasOpen gen=$($script:RecoveryGeneration)"
    }
    $script:ForceCursorAuthSync = $true
    $script:PostTunnelRecovery = $true
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'RECOVERY_STATE_RESET editor_opened=False force_auth=True post_recovery=True'
    }
}

function Complete-PostTunnelRecovery {
    param(
        [bool]$MountOk,
        [string]$AuthDetail = '',
        [string]$ProjectId = '',
        [string]$RemotePath = '',
        [string]$EditorCmd = '',
        [string]$EditorName = '',
        [bool]$OnFolder = $false,
        [bool]$DidLaunch = $false
    )
    if (-not $script:PostTunnelRecovery) { return }
    $elapsed = 0
    if ($script:RecoveryStartedAt) {
        $elapsed = [int]((Get-Date) - $script:RecoveryStartedAt).TotalMilliseconds
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "RECOVERY_END elapsed_ms=$elapsed mount_ok=$MountOk gen=$($script:RecoveryGeneration) auth=$AuthDetail"
    }
    if (Get-Command Write-ConnectDiagnosticReport -ErrorAction SilentlyContinue) {
        $authOk = ($AuthDetail -match 'ok|already|skipped' -and $AuthDetail -notmatch 'fail|incomplete|missing')
        $null = Write-ConnectDiagnosticReport -Phase 'RECOVERY' `
            -EditorCmd $EditorCmd -EditorName $EditorName -Alias $Alias `
            -ProjectId $ProjectId -RemotePath $RemotePath `
            -TunnelUp (Test-TunnelUp) -MountOk $MountOk -OnFolder $OnFolder `
            -DidLaunch $DidLaunch -AuthOk $authOk -AuthDetail $AuthDetail `
            -ServerIP $ServerIP -Port $Port `
            -SshRecent @($script:SshRecentLog)
    }
    $script:PostTunnelRecovery = $false
    $script:RecoveryStartedAt = $null
}

function Write-SessionDiagnosticReport {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [bool]$MountOk = $true,
        [string]$MountOut = '',
        [bool]$OnFolder = $false,
        [bool]$DidLaunch = $false,
        [bool]$AuthOk = $true,
        [string]$AuthDetail = '',
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$EditorName
    )
    if (-not (Get-Command Write-ConnectDiagnosticReport -ErrorAction SilentlyContinue)) { return $null }
    $agentHome = $false
    $windowOpen = $false
    if ($EditorCmd -eq 'cursor') {
        if (Get-Command Test-RemoteEditorInAgentHome -ErrorAction SilentlyContinue) {
            $agentHome = Test-RemoteEditorInAgentHome
        }
        if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
            $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }
    }
    return Write-ConnectDiagnosticReport -Phase $Phase `
        -EditorCmd $EditorCmd -EditorName $EditorName -Alias $Alias `
        -ProjectId $ProjectId -RemotePath $RemotePath `
        -TunnelUp (Test-TunnelUp) -MountOk $MountOk -MountOut $MountOut `
        -OnFolder $OnFolder -AgentHome $agentHome -WindowOpen $windowOpen `
        -DidLaunch $DidLaunch -AuthOk $AuthOk -AuthDetail $AuthDetail `
        -ServerIP $ServerIP -Port $Port `
        -SshRecent @($script:SshRecentLog)
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
    $existing = @(Get-Mounts) | Where-Object { $_.Id -eq $nId }
    if ($existing.Count -gt 0) {
        Warn "Project '$nId' already exists. Enter a different name."
        return $null
    }
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
            return ,([PSCustomObject]@{ Id = $m.Id; Path = $m.Path; Rpath = $m.Rpath })
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
                            @("REMOTE_USER=$nUser", "LAPTOP_USER=$(Get-InteractiveLaptopUser)") | Set-Content -Path $Cfg -Encoding ASCII
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
    $laptopUser = Get-InteractiveLaptopUser
    @("REMOTE_USER=$RemoteUser", "LAPTOP_USER=$laptopUser") | Set-Content -Path $Cfg -Encoding ASCII
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
if (Test-IsAdmin) { Initialize-EditorLaunchTask | Out-Null }
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
Sanitize-SshAliasConfig -CfgPath $sshCfg -AliasName $Alias
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
            @("REMOTE_USER=$fix", "LAPTOP_USER=$(Get-InteractiveLaptopUser)") | Set-Content -Path $Cfg -Encoding ASCII
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
else { StepOk "port $Port slot=$($script:TunnelSlot) git=$(Get-GitMode)" }
$PubB = $boot.PubB

Write-Host ''
Write-Host '    Ready' -ForegroundColor Green
Write-Host ''
Mark-BootstrapDone -CfgDir $CfgDir
$null = Ensure-LaptopSshReady -PubB $PubB
$script:LaptopSshVerified = $false
$script:SessionBgTunnel = $null
$null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

$script:tunnelAuthAdminFixAttempted = $false
$exitRequested = $false
:menuLoop while (-not $exitRequested) {
    Step "Loading projects"
    $null = ($allMounts = @(Get-Mounts))
    StepOk (Get-MountListStepLabel -Os 'windows' -Mounts $allMounts)
    $go = @(Choose-Project -Mounts $allMounts)[-1]
    if (-not $go) { break }
    Write-ConnectLog "PROJECT: id=$($go.Id) server_path=$($go.Path) laptop_path=$($go.Rpath)"
    $script:tunnelAuthAdminFixAttempted = $false
    $script:tunnelAuthRetryCount = 0

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

    $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

    $editorOpened = $false
    $script:CursorAuthNeedsBootstrap = $false
    $script:RecoveryGeneration = 0
    $script:SessionLoopIter = 0
    $script:ForceCursorAuthSync = $false
    $script:PostTunnelRecovery = $false
    $script:RecoveryStartedAt = $null
    $script:SshRecentLog = [System.Collections.Generic.List[string]]::new()
    $script:LastAuthDetail = ''

    :mainLoop while ($true) {
    $alreadyDown  = $false
    $bgTunnel     = $script:SessionBgTunnel

    try {
        :sessionLoop while ($true) {
            $script:SessionLoopIter++
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog "SESSION_LOOP begin iter=$($script:SessionLoopIter) recovery_gen=$($script:RecoveryGeneration) post_recovery=$($script:PostTunnelRecovery) force_auth=$($script:ForceCursorAuthSync)"
            }
            $tunnelReused = $false
            if (-not (Ensure-SessionTunnel -Alias $Alias -SshCfgPath $sshCfg -BgTunnel ([ref]$bgTunnel) -TunnelReused ([ref]$tunnelReused))) {
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
            $script:SessionBgTunnel = $bgTunnel
            if (-not $tunnelReused) {
                # Wait-ForTunnelUp already printed progress lines
            } elseif ($tunnelReused) {
                Step 'SSH tunnel'
                StepOk "reusing pid $($bgTunnel.Id)"
            }

            $mountSrc = Get-ClaudeMountSrc -ConnectScriptDir $script:ConnectScriptDir
            Prepare-ServerSessionParallel -ProjectId $go.Id -MountSrc $mountSrc -Alias $Alias
            $activeOnServer = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null") -join '').Trim()
            Write-ConnectLog "ACTIVE_MOUNT server_conf=$activeOnServer pushed_id=$($go.Id)"

            Invoke-RecoverIfNeeded -ProjectId $go.Id -FreshTunnel:(-not $tunnelReused)

            if (-not (Test-TunnelUp)) {
                Write-Host "      -> tunnel dropped during recover, restarting..." -ForegroundColor DarkGray
                $script:LaptopSshVerified = $false
                continue
            }

            Step 'Verifying laptop SSH key'
            $laptopSshRc = Ensure-LaptopReverseSshCached -PubB $PubB
            if ($laptopSshRc -eq 0) {
                StepOk
            } elseif ($laptopSshRc -eq 1) {
                $script:tunnelAuthRetryCount++
                $failDetail = if ($script:LastLaptopReverseSshError) { $script:LastLaptopReverseSshError } else { 'tunnel auth failed' }
                StepFail $failDetail
                if ($failDetail -match 'Host key verification failed|Offending') {
                    Write-Host '      -> clearing stale server known_hosts for tunnel port...' -ForegroundColor DarkGray
                    Clear-ServerTunnelKnownHost
                    $script:LaptopSshVerified = $false
                } elseif ($PubB -and -not $script:tunnelAuthAdminFixAttempted) {
                    $script:tunnelAuthAdminFixAttempted = $true
                    Write-Host '      -> reinstalling server key (admin authorized_keys)...' -ForegroundColor DarkGray
                    $null = Invoke-LaptopAdminOps -PubB $PubB -ForceRestart
                    Clear-ServerTunnelKnownHost
                    $script:LaptopSshVerified = $false
                }
                if ($script:tunnelAuthRetryCount -ge 5) {
                    Write-Host ''
                    Warn 'Tunnel auth failed 5 times - check sshd service and administrators_authorized_keys'
                    Write-Host '    R = retry   Q = quit' -ForegroundColor DarkGray
                    $rk = Read-RetryQuitKey
                    if ($rk -eq 'r') {
                        $script:tunnelAuthRetryCount = 0
                        $script:tunnelAuthAdminFixAttempted = $false
                        Write-Host ''
                        continue
                    }
                    Push-ServerConnectConf -ActiveMount ''
                    $alreadyDown = $true; break sessionLoop
                }
                Write-Host ''
                continue
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
                    $script:LaptopSshVerified = $false
                    if (-not (Test-TunnelUp)) {
                        Write-Host ''; Warn 'Tunnel dropped after sshd restart - reconnecting...'
                        continue
                    }
                    $postRestartRc = Ensure-LaptopReverseSshCached -PubB $newPub
                    if ($postRestartRc -ne 0) {
                        StepFail 'tunnel auth failed after sshd restart'
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
                Complete-PostTunnelRecovery -MountOk $false -AuthDetail 'mount_failed' `
                    -ProjectId $go.Id -RemotePath $go.Path -EditorCmd $EditorCmd -EditorName $EditorName
                Write-Host ""
                Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
                $rk = Read-RetryQuitKey
                if ($rk -eq 'r') { Write-Host ""; continue }
                Push-ServerConnectConf -ActiveMount ''
                $alreadyDown = $true; break sessionLoop
            }

            StepOk "${mountT}s"
            Show-MountGitWarn $mountOut
            Write-ConnectLog "MOUNT_RAW: $($mountOut.Trim() -replace '\s+', ' ')"
            $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '' -replace '^mounted:\s*', '')
            $cleanOut = (($cleanOut -split '\r?\n')[0]).Trim()
            if ($cleanOut -and $cleanOut -notmatch '^warn:') {
                Write-Host "      -> $cleanOut" -ForegroundColor Green
                Write-ConnectLog "MOUNT: $cleanOut"
            }
            if ($script:PostTunnelRecovery) {
                Warn 'Recovery complete - press O if Cursor is not on the project folder'
                Write-ConnectLog 'RECOVERY: user_warn press_o_if_cursor_not_on_folder'
            }

            $script:ActiveProjectId = $go.Id

            $script:CursorAuthNeedsBootstrap = $false
            $script:LastAuthDetail = if ($EditorCmd -eq 'cursor') { 'pending' } else { 'n/a' }
            $onCorrectFolder = $false
            $agentHome = $false
            if ($EditorCmd -eq 'cursor' -and (Get-Command Sync-CursorGoldenAuth -ErrorAction SilentlyContinue)) {
                $gsPath = Join-Path (Get-LocalCursorGlobalStorage) 'state.vscdb'
                $folderSw = [System.Diagnostics.Stopwatch]::StartNew()
                $onCorrectFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                $agentHome = Test-RemoteEditorInAgentHome -RemotePath $go.Path
                $cursorRunning = $false
                if ($onCorrectFolder -and (Get-Command Test-RemoteEditorWindowOpenWhenOnFolder -ErrorAction SilentlyContinue)) {
                    $cursorRunning = Test-RemoteEditorWindowOpenWhenOnFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                }
                $folderSw.Stop()
                if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                    Write-ConnectPerfLog -Mark 'auth_folder_check' -Ms $folderSw.ElapsedMilliseconds `
                        -Extra "on_folder=$onCorrectFolder window=$cursorRunning agent_home=$agentHome"
                }
                Write-ConnectLog "FOLDER_CHECK: on_folder=$onCorrectFolder agent_home=$agentHome window_open=$cursorRunning" 'DEBUG'
                $verboseLaunch = ($env:CLAUDE_CONNECT_VERBOSE_LAUNCH -eq '1')
                if ($verboseLaunch -and (Get-Command Get-RemoteEditorLaunchDiag -ErrorAction SilentlyContinue)) {
                    Write-ConnectLog (Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) 'DEBUG'
                } elseif (-not $verboseLaunch -and (Get-Command Get-RemoteEditorDetectionDiag -ErrorAction SilentlyContinue)) {
                    Write-ConnectLog "AUTH_CHECK: cursor_running=$cursorRunning on_folder=$onCorrectFolder" 'DEBUG'
                }
                Step "Syncing Cursor auth"
                $authComplete = Test-LocalCursorAuthComplete -DbPath $gsPath
                $authNeedsRefresh = $false
                if (Get-Command Test-CursorAuthNeedsRefresh -ErrorAction SilentlyContinue) {
                    $refreshCheck = Test-CursorAuthNeedsRefresh -DbPath $gsPath
                    $authNeedsRefresh = [bool]$refreshCheck.NeedsRefresh
                    if ($authNeedsRefresh -and $refreshCheck.Reasons.Count -gt 0) {
                        Write-ConnectLog "AUTH_DECISION needs_refresh reason=$($refreshCheck.Reasons -join ',')" 'DEBUG'
                    }
                }
                if (Get-Command Test-PersonalCursorDominant -ErrorAction SilentlyContinue) {
                    if (Test-PersonalCursorDominant) {
                        Warn 'Personal Cursor is open - close it or use [Claude Server] profile windows'
                        Write-ConnectLog 'AUTH_WARN personal_cursor_dominant' 'WARN'
                    }
                }
                $skipAuth = $false
                if (-not $script:ForceCursorAuthSync -and -not $script:PostTunnelRecovery -and -not $authNeedsRefresh) {
                    if ($cursorRunning -and $authComplete) { $skipAuth = $true }
                }
                Write-ConnectLog "AUTH_DECISION skip=$skipAuth force=$($script:ForceCursorAuthSync) post_recovery=$($script:PostTunnelRecovery) cursor_running=$cursorRunning auth_complete=$authComplete"
                if ($skipAuth) {
                    StepOk 'skipped (editor open)'
                    $script:LastAuthDetail = 'skipped editor open'
                } else {
                    $authSync = Sync-CursorGoldenAuth -Alias $Alias -Force:$script:ForceCursorAuthSync
                    if ($authSync.Skipped) {
                        if ($authSync.AlreadyComplete) {
                            StepOk 'already ok'
                            $script:LastAuthDetail = 'already ok'
                            if ($script:ForceCursorAuthSync) { $script:ForceCursorAuthSync = $false }
                        }
                        else {
                            StepOk 'skipped'
                            $script:LastAuthDetail = 'skipped'
                        }
                    }
                    elseif ($authSync.Ok) {
                        StepOk
                        $script:LastAuthDetail = 'ok'
                        $script:ForceCursorAuthSync = $false
                        Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'cursor-auth.ok')) -Value (Get-Date -Format 'o') -Encoding ASCII | Out-Null
                    }
                    elseif ($authSync.TokensOnly) {
                        StepOk 'tokens only'
                        $script:LastAuthDetail = 'tokens only'
                        Warn 'Partial auth on laptop - reconnect, or ask admin to run: sudo claude-server sync-cursor-auth'
                    }
                    elseif ($authSync.SqliteMissing) {
                        StepFail 'sqlite not available on laptop'
                        $script:LastAuthDetail = 'sqlite missing'
                        Warn 'Windows winsqlite3.dll or sqlite3.dll is required for auth merge'
                    }
                    elseif ($authSync.MergeFailed) {
                        StepFail 'could not merge server auth'
                        $script:LastAuthDetail = 'merge failed'
                        Warn 'Close all [Claude Server] Cursor windows and reconnect'
                    }
                    else {
                        StepFail 'could not merge server auth'
                        $script:LastAuthDetail = 'merge failed'
                        Warn 'Server auth is OK - laptop could not save it locally (reconnect or close Cursor windows)'
                    }
                }
                if (-not $onCorrectFolder -and (Get-Command Repair-CursorComposerWorkspaceBindings -ErrorAction SilentlyContinue)) {
                    $null = Repair-CursorComposerWorkspaceBindings -Alias $Alias -RemotePath $go.Path
                }
            }

            $didLaunch = $false
            if (-not $editorOpened) {
                Step "Opening $EditorName"
                if (-not (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -KnownOnFolder:$onCorrectFolder)) {
                    StepFail "$EditorName not found (install Cursor or VS Code + Remote-SSH)"
                } else {
                    StepOk $($go.Path)
                    $didLaunch = $true
                    if ($EditorCmd -eq 'cursor') {
                        Write-Host '      -> Server profile [Claude Server] - personal Cursor is separate' -ForegroundColor DarkGray
                    }
                }
                Write-Host ""
                Write-Host "    Run 'claude' in the $EditorName terminal." -ForegroundColor DarkGray
            }
            $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            if (-not $onFolderNow -and ($didLaunch -or (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path))) {
                Write-ConnectLog 'SESSION: cursor not on target folder - relaunching with new-window' 'WARN'
                if (-not $didLaunch) {
                    Warn 'Cursor is on Agent/home - reopening project folder...'
                }
                if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                }
            }
            $editorOpened = $onFolderNow

            $sessionExtras = @()
            if ($EditorCmd -eq 'cursor') {
                if ($script:LastAuthDetail -match '^(ok|tokens only)$') {
                    $sessionExtras += 'Chat: Developer -> Reload Window if messages fail'
                }
            }
            if ($script:ConnectLogPath) {
                $sessionExtras += "Log: $(Split-Path -Leaf $script:ConnectLogPath) (same folder as connect.bat)"
            }
            Write-SessionBox -ExtraLines $sessionExtras
            Set-ConnectTitle ('Claude Connect | {0} | {1}' -f $go.Id, (Get-GitModeLabel))

            $authOkForDiag = ($script:LastAuthDetail -match '^(ok|already ok|skipped|tokens only|n/a)$')
            $diagSw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Write-SessionDiagnosticReport -Phase 'SESSION_OPEN' -MountOk $true -MountOut $mountOut `
                -OnFolder $onFolderNow -DidLaunch $didLaunch -AuthOk $authOkForDiag `
                -AuthDetail $script:LastAuthDetail -ProjectId $go.Id -RemotePath $go.Path `
                -EditorCmd $EditorCmd -EditorName $EditorName
            $diagSw.Stop()
            if ($script:ConnectPerf) { $script:ConnectPerf.DiagMs = [int]$diagSw.ElapsedMilliseconds }
            if (Get-Command Write-ConnectSessionOpenSummary -ErrorAction SilentlyContinue) {
                Write-ConnectSessionOpenSummary
            }
            Complete-PostTunnelRecovery -MountOk $true -AuthDetail $script:LastAuthDetail `
                -ProjectId $go.Id -RemotePath $go.Path -EditorCmd $EditorCmd -EditorName $EditorName `
                -OnFolder $onFolderNow -DidLaunch $didLaunch

            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

            $action = 'q'
            $gotKey = $false
            $lastStatusAt = [DateTime]::MinValue
            $script:lastToastAt = $null
            while ($true) {
                $null = Sync-SessionTunnelProcess -BgTunnel ([ref]$bgTunnel)
                if (-not (Test-TunnelUp)) { break }
                if ($EditorCmd -eq 'cursor') {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $editorOpened = $onFolderNow
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } else { 'closed' }
                } else {
                    $onFolderNow = $editorOpened
                    $editorLabel = ''
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk (Test-TunnelUp) `
                        -EditorOpen $onFolderNow -EditorName $EditorName -EditorLabel $editorLabel `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }

                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 200
            }
            if (-not $gotKey -and -not (Test-TunnelUp)) {
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
                    Write-ConnectLog 'TUNNEL: connection dropped - auto reconnect' 'WARN'
                    Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
                }
            }

            if ($action -eq 'g') {
                Configure-GitMode
                continue sessionLoop
            }

            if ($action -eq 'o') {
                $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                if (-not $onFolderNow) {
                    Write-Host ''
                    Step "Reopening $EditorName"
                    if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                        StepOk $go.Path
                        $editorOpened = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    } else {
                        StepFail "$EditorName not found"
                    }
                    Write-Host ''
                }
                continue sessionLoop
            }

            if ($action -eq 'r') {
                if ($gotKey) {
                    Begin-ConnectRecovery -Trigger 'manual' -ProjectId $go.Id -EditorWasOpen $editorOpened
                    $editorOpened = $false
                    $script:LaptopSshVerified = $false
                    $alreadyDown = $false
                    Write-Host ''
                    Write-Host '    Reconnecting...' -ForegroundColor Cyan
                    Write-Host ''
                    continue sessionLoop
                }
                Begin-ConnectRecovery -Trigger 'auto' -ProjectId $go.Id -EditorWasOpen $editorOpened
                $editorOpened = $false
                Write-Host '    Connection dropped - recovering...' -ForegroundColor Yellow
                Write-ConnectLog 'TUNNEL: recovering session (down mount, restart tunnel)' 'WARN'
                Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop
                Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
                $alreadyDown = $true
                $script:LaptopSshVerified = $false
                Write-Host ''
                continue sessionLoop
            }

            # Disconnect (Q)
            Write-Host ""
            Write-Host "    Disconnecting..." -ForegroundColor DarkGray
            Write-ConnectLog "SESSION: disconnect project=$($go.Id)"
            Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
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
        # Always kill tunnel + clear server forward (even if $alreadyDown from Q path)
        Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
    }

    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

    $postKey = Read-PostDisconnectKey -DefaultChar M -TimeoutSec 10
    switch ($postKey) {
        'm' {
            Write-Host '    Back to project menu...' -ForegroundColor Green
            $editorOpened = $false
            $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet
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
Close-ConnectLog





