#Requires -Version 5.1
# Task 7: folded open-port prefetch, warm foreign-session skip, bootstrap remote-ver disk cache.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Task 7 prefetch / foreign skip / remote-ver cache ===' -ForegroundColor Cyan

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$boot = Get-Content (Get-ClientFile 'windows\connect-bootstrap.ps1') -Raw

Write-Host ''
Write-Host '--- A) Fold open-port batch into Initialize-ServerSession ---' -ForegroundColor DarkCyan

$initFn = Get-FunctionSource -Content $connect -Name 'Initialize-ServerSession'
Assert ($initFn -match 'OPEN:\$p|echo OPEN:') 'init ssh includes OPEN: port probe markers'
Assert ($initFn -match 'Import-PrefetchedOpenTunnelPorts') 'init calls Import-PrefetchedOpenTunnelPorts'
Assert ($gm -match 'function Import-PrefetchedOpenTunnelPorts') 'git-mode defines Import-PrefetchedOpenTunnelPorts'
Assert ($gm -match 'function Get-PrefetchedOpenTunnelPortSet') 'git-mode defines Get-PrefetchedOpenTunnelPortSet'
$acq = Get-FunctionSource -Content $gm -Name 'Acquire-TunnelPort'
Assert ($acq -match 'Get-PrefetchedOpenTunnelPortSet') 'Acquire-TunnelPort uses prefetched batch when present'

# Behavioral: prefetched batch avoids Get-ServerOpenTunnelPorts ssh.
$script:sshCount = 0
function SshX { param($cmd) $script:sshCount++; return '' }
function Write-GitModeLog { param($m, $lvl) }
$script:TunnelTcpStateCache = @{}
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Set-TunnelTcpState')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Get-TunnelPortUserBase')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Import-PrefetchedOpenTunnelPorts')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Get-PrefetchedOpenTunnelPortSet')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Get-ServerOpenTunnelPorts')))

$null = Import-PrefetchedOpenTunnelPorts -Lines @('1000', 'OPEN:20001') -UidStr '1000'
$script:sshCount = 0
$set = Get-PrefetchedOpenTunnelPortSet -Ports @(20001)
Assert ($null -ne $set) 'prefetch returns HashSet for covered port'
Assert ($set.Contains(20001)) 'prefetch marks probed open port'
Assert ($script:sshCount -eq 0) 'prefetch path issues ZERO ssh for open-port batch'

Write-Host ''
Write-Host '--- B) Warm local conf foreign-session skip ---' -ForegroundColor DarkCyan

Assert ($gm -match 'function Test-WarmLocalConfForeignSkip') 'Test-WarmLocalConfForeignSkip defined'
$warn = Get-FunctionSource -Content $gm -Name 'Warn-ForeignServerSession'
Assert ($warn -match 'Test-WarmLocalConfForeignSkip') 'Warn-ForeignServerSession consults warm local skip'
Assert ($warn -match 'warm_local_conf') 'Warn-ForeignServerSession logs warm_local_conf skip'

$tmp = Join-Path $env:TEMP ("claude-connect-task7-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$cfg = Join-Path $tmp 'connect.conf'
@"
LAPTOP_USER=$env:USERNAME
TUNNEL_SLOT=1
PORT=20001
TUNNEL_PORT=20001
"@ | Set-Content -Path $cfg -Encoding ASCII

$Cfg = $cfg
$script:LaptopUser = $env:USERNAME
function Write-GitModeLog { param($m, $lvl) }
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Test-WarmLocalConfForeignSkip')))
Assert (Test-WarmLocalConfForeignSkip) 'warm local conf passes for matching laptop user + port + slot'
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- C) Bootstrap remote-ver disk cache (15m TTL) ---' -ForegroundColor DarkCyan

Assert ($boot -match 'claude-connect-remote-ver\.cache') 'bootstrap references remote-ver cache file'
Assert ($boot -match 'RemoteVerCacheTtlMinutes\s*=\s*15') 'bootstrap TTL is 15 minutes'
Assert ($boot -match 'Read-RemoteVerDiskCache') 'bootstrap reads remote-ver cache'
Assert ($boot -match 'Write-RemoteVerDiskCache') 'bootstrap writes remote-ver cache'
Assert ($boot -match 'Clear-RemoteVerDiskCache') 'bootstrap clears remote-ver cache on pull/force'
Assert ($boot -match 'skip remote ver ssh cache hit') 'bootstrap logs cache hit skip'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red
exit 1
