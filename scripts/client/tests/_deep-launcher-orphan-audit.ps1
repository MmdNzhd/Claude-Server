# DEEP launcher/orphan audit — evidence over claims.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

$pass = 0; $fail = 0; $warn = 0
function Ok([string]$m) { $script:pass++; Write-Host "PASS  $m" -ForegroundColor Green }
function Bad([string]$m) { $script:fail++; Write-Host "FAIL  $m" -ForegroundColor Red }
function Warn([string]$m) { $script:warn++; Write-Host "WARN  $m" -ForegroundColor Yellow }
function Note([string]$m) { Write-Host "NOTE  $m" -ForegroundColor DarkGray }

function Get-ConnectRelatedCmds {
    @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -match 'Claude-Connect\.cmd|Claude-Connect\.vbs|connect-boot\.ps1|start \"Claude Connect\"|/D \".*\\src\"'
    })
}

function Get-SshdCmds {
    @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $par = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.ParentProcessId)" -ErrorAction SilentlyContinue
        $par -and $par.Name -eq 'sshd.exe'
    })
}

function Test-LauncherFiles([string]$VerDir, [string]$Label) {
    $cmd = Join-Path $VerDir 'Claude-Connect.cmd'
    $vbs = Join-Path $VerDir 'Claude-Connect.vbs'
    if (-not (Test-Path $cmd)) { Warn "$Label no Claude-Connect.cmd"; return }
    $c = Get-Content -LiteralPath $cmd -Raw
    $old = ($c -match 'start\s+"Claude Connect"') -or ($c -match 'powershell\.exe' -and $c -notmatch 'wscript')
    $neu = ($c -match 'wscript\.exe') -and ($c -match 'Claude-Connect\.vbs') -and ($c -match 'exit /b 0')
    $hasVbs = Test-Path $vbs
    if ($neu -and $hasVbs -and -not $old) { Ok "$Label VBS trampoline OK" }
    elseif ($old) { Bad "$Label OLD start-powershell launcher" }
    else { Bad "$Label incomplete launcher new=$neu vbs=$hasVbs old=$old" }
    if ($hasVbs) {
        $v = Get-Content -LiteralPath $vbs -Raw
        if ($v -match 'WScript\.Shell' -and $v -match 'connect-boot\.ps1' -and $v -match 'sh\.Run') { Ok "$Label VBS body OK" }
        else { Bad "$Label VBS body weak/missing Run" }
    }
}

Write-Host '======== A) SOURCE CONTRACTS ========' -ForegroundColor Cyan
$setup = Get-Content (Join-Path $RepoRoot 'publish\_setup-launch-body.ps1') -Raw
$upd = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
$ver = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
Note "repo_version=$ver"
if ($setup -match 'wscript\.exe //B //Nologo' -and $setup -notmatch 'start "Claude Connect" /D') { Ok 'setup-launch VBS-only contract' } else { Bad 'setup-launch contract broken' }
if ($upd -match 'function Write-ConnectInstantLauncher' -and $upd -match 'Write-ConnectInstantLauncher -VerDir \$newVerDir' -and $upd -match 'Refresh VBS trampoline') { Ok 'connect-update writes launcher on apply + up-to-date' } else { Bad 'connect-update missing launcher refresh gates' }
if ($ver -eq '20260727.24') { Ok 'repo pinned 20260727.24' } else { Warn "repo version is $ver (expected 20260727.24)" }

Write-Host '======== B) ON-DISK VERDIR LAUNCHERS ========' -ForegroundColor Cyan
$roots = @((Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'), 'C:\Temp\Claude-Connect')
foreach ($root in $roots) {
    if (-not (Test-Path $root)) { Warn "missing $root"; continue }
    $dirs = @(Get-ChildItem $root -Directory -EA SilentlyContinue | Where-Object { $_.Name -match '^\d{8}\.\d+$' })
    Note "$root count=$($dirs.Count)"
    foreach ($d in $dirs) { Test-LauncherFiles -VerDir $d.FullName -Label "$root\$($d.Name)" }
}

Write-Host '======== C) SERVER BUNDLE ========' -ForegroundColor Cyan
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path $ssh)) { $ssh = 'ssh' }
# Avoid PowerShell expanding $(...) inside the remote script: pass a single-quoted remote command.
$remoteCmd = 'B=/usr/local/share/claude-client; echo VER=$(cat $B/connect-version.txt); echo UPD_FN=$(grep -c function\ Write-ConnectInstantLauncher $B/connect-update.ps1); echo UPD_WSCRIPT=$(grep -c wscript.exe $B/connect-update.ps1); echo PREFLIGHT=$(test -f $B/connect-preflight.ps1 && echo yes || echo no); echo PRE_HASH=$(grep -c connect-preflight.ps1 $B/checksums.txt || true); U=$(sha256sum $B/connect-update.ps1 | awk ''{print $1}''); G=$(awk ''/ connect-update\.ps1$/{print $1}'' $B/checksums.txt); if [ "$U" = "$G" ]; then echo HASH=match; else echo HASH=MISMATCH; fi'
$remote = & $ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 $remoteCmd 2>&1
$remote | ForEach-Object { Note "$_" }
$rj = ($remote | Out-String)
if ($rj -match 'VER=20260727\.24') { Ok 'server VER=20260727.24' } else { Bad "server version not 24: $rj" }
if ($rj -match 'HASH=match') { Ok 'server connect-update checksum matches' } else { Bad 'server checksum mismatch' }
if ($rj -match 'UPD_FN=[1-9]' -and $rj -match 'UPD_WSCRIPT=[1-9]') { Ok 'server update has VBS launcher writer' } else { Bad 'server update missing VBS writer' }
if ($rj -match 'PREFLIGHT=yes' -and $rj -match 'PRE_HASH=[1-9]') { Ok 'server preflight present+hashed' } else { Warn 'server preflight hash/presence weak' }

Write-Host '======== D) BASELINE PROCESS SNAPSHOT ========' -ForegroundColor Cyan
$baseConnect = @(Get-ConnectRelatedCmds)
$baseSshd = @(Get-SshdCmds)
Note ("baseline connect-related cmd={0} sshd-cmd={1}" -f $baseConnect.Count, $baseSshd.Count)
if ($baseConnect.Count -eq 0) { Ok 'baseline: no Connect-launcher cmd orphans' } else {
    foreach ($p in $baseConnect) { Bad ("baseline orphan cmd pid={0} cmd={1}" -f $p.ProcessId, $p.CommandLine) }
}
Warn ("baseline sshd cmd shells={0} (expected while tunnel up; not launcher)" -f $baseSshd.Count)

Write-Host '======== E) LIVE TRAMPOLINE STORM (sandbox only) ========' -ForegroundColor Cyan
# Never storm the real Desktop VerDir (would spawn real Connect UIs / eat slots).
$sandbox = $true
$probeRoot = Join-Path $env:TEMP ("deep-launch-{0}\20260727.99" -f [guid]::NewGuid().ToString('N'))
$src = Join-Path $probeRoot 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null
$marker = Join-Path $env:TEMP ("deep-launch-marker-{0}.txt" -f [guid]::NewGuid().ToString('N'))
if (Test-Path $marker) { Remove-Item $marker -Force }
$bootBody = @"
`$ErrorActionPreference='Stop'
Set-Content -LiteralPath '$marker' -Value ("boot ok pid=`$PID ts=`$(Get-Date -Format o)") -Encoding ASCII
Start-Sleep -Milliseconds 400
exit 0
"@
Set-Content -LiteralPath (Join-Path $src 'connect-boot.ps1') -Value $bootBody -Encoding ASCII
$fn = Get-FunctionSource -Content $upd -Name 'Write-ConnectInstantLauncher'
Invoke-Expression 'function Write-UpdateFileLog { param($Message,$Level=''INFO'') }'
Invoke-Expression $fn
Write-ConnectInstantLauncher -VerDir $probeRoot -SrcDir $src
Ok 'sandbox VerDir prepared with production Write-ConnectInstantLauncher from connect-update.ps1'

$cmdPath = Join-Path $probeRoot 'Claude-Connect.cmd'
$before = @(Get-ConnectRelatedCmds | ForEach-Object { $_.ProcessId })
# Triple rapid .cmd launches
1..3 | ForEach-Object {
    Start-Process -FilePath $cmdPath -WorkingDirectory $probeRoot -WindowStyle Minimized
    Start-Sleep -Milliseconds 120
}
Start-Sleep -Seconds 2
$after = @(Get-ConnectRelatedCmds)
$newOrphans = @($after | Where-Object { $before -notcontains $_.ProcessId })
# Filter: trampoline should exit; lingering cmd hosting Claude-Connect.cmd is bad
$badOrphans = @($newOrphans | Where-Object {
    $c = [string]$_.CommandLine
    # minimized wscript start line may appear briefly; fail only if still alive AND looks like old powershell start or stuck on .cmd without exit
    ($c -match 'start \"Claude Connect\"') -or ($c -match 'Claude-Connect\.cmd' -and $c -notmatch 'wscript')
})
if ($badOrphans.Count -eq 0) { Ok ("storm: 3x .cmd launch left 0 bad orphans (connect-related after={0})" -f $after.Count) }
else {
    foreach ($o in $badOrphans) { Bad ("storm orphan pid={0} cmd={1}" -f $o.ProcessId, $o.CommandLine) }
}

if ($sandbox) {
    Start-Sleep -Seconds 1
    if (Test-Path $marker) { Ok 'sandbox boot marker written via VBS path' } else { Bad 'sandbox boot marker missing (VBS/cmd did not reach connect-boot)' }
    # Count cmd still pointing at our sandbox after 1s
    $stuck = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -EA SilentlyContinue | Where-Object {
        ([string]$_.CommandLine) -match [regex]::Escape($probeRoot)
    })
    if ($stuck.Count -eq 0) { Ok 'sandbox: no cmd still referencing probe VerDir after 1s' }
    else { foreach ($s in $stuck) { Bad ("sandbox stuck cmd pid={0} cmd={1}" -f $s.ProcessId, $s.CommandLine) } }
    Remove-Item -LiteralPath (Split-Path $probeRoot -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $marker) { Remove-Item $marker -Force -EA SilentlyContinue }
}

Write-Host '======== F) HARDER LIVE SUITE ========' -ForegroundColor Cyan
$t = Join-Path $PSScriptRoot 'test-harder-live-instant-launcher.ps1'
$r = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $t 2>&1
$code = $LASTEXITCODE
$tail = ($r | Select-Object -Last 2) -join ' | '
if ($code -eq 0) { Ok "harder-live-instant-launcher $tail" } else { Bad "harder-live-instant-launcher exit=$code $tail" }

Write-Host '======== G) OTHER CMD SOURCES (honest) ========' -ForegroundColor Cyan
$bat = Get-Content (Get-ClientFile 'windows\connect.bat') -Raw
if ($bat -match 'BAT_INNER' -and $bat -match '/MIN') {
    Bad 'connect.bat BAT_INNER still uses /MIN (taskbar-visible console)'
} elseif ($bat -match 'connect-hide-relaunch\.vbs' -and $bat -match 'connect-hide-console\.ps1') {
    Ok 'connect.bat BAT_INNER uses VBS style-0 + hide-console belt'
} else { Warn 'connect.bat BAT_INNER pattern unexpected' }
Note 'IExpress Claude-Connect-*.exe extract may flash a console during wextract; separate from instant .cmd/.vbs path'
Note 'sshd.exe child cmd.exe = reverse-tunnel shells while Connect session is up'

Write-Host ("======== DEEP RESULT pass={0} fail={1} warn={2} ========" -f $pass, $fail, $warn) -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
