#Requires -Version 5.1
# Task 8: Server setup deferred until after project_menu_shown; still runs before tunnel/mount.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Task 8 deferred Server setup contract ===' -ForegroundColor Cyan
Write-Host ''

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

Assert ($connect -match 'function Start-DeferredServerSetup') 'Start-DeferredServerSetup defined'
Assert ($connect -match 'function Wait-DeferredServerSetup') 'Wait-DeferredServerSetup defined'
Assert ($connect -match 'function Get-DeferredServerSetupTimeoutMs') 'Get-DeferredServerSetupTimeoutMs defined'
Assert ($connect -match 'function Ensure-ServerSessionReady') 'Ensure-ServerSessionReady defined'
Assert ($connect -match 'DeferredServerSetupOnly') 'connect.ps1 supports DeferredServerSetupOnly child runner'
Assert ($connect -match 'SERVER_SETUP deferred=1') 'deferred setup is logged'
Assert ($connect -match 'SERVER_SETUP_TIMEOUT ms=') 'Wait-DeferredServerSetup has greppable timeout log'
Assert ($connect -match 'deferred_setup_skip_mutex') 'deferred child skips UI mutex (multi-agent safe)'
Assert ($connect -match '(?s)if \(\$DeferredServerSetupOnly\)[\s\S]{0,900}elseif \(-not \(Enter-ConnectSingleInstance\)\)') 'Enter-ConnectSingleInstance not called for deferred child'
Assert ($connect -match 'inherit_slot') 'deferred start preserves parent UI_SLOT'
Assert ($connect -match 'deferred_setup_ssh_dir_not_running_profile') `
    'DeferredServerSetupOnly child pins IdentityFile when ssh dir rebound'
Assert ($connect -match '(?s)DeferredServerSetupOnly\)[\s\S]+?ConnectSshIdentityFile[\s\S]+?Set-SshHostBlock[\s\S]+?Initialize-ServerSession') `
    'Identity pin runs inside DeferredServerSetupOnly before Set-SshHostBlock / Initialize-ServerSession'

$readyToMenu = [regex]::Match($connect, '(?s)Mark-BootstrapDone[\s\S]*?INTERACTIVE: project_menu_shown').Value
Assert ($readyToMenu -and ($readyToMenu -notmatch 'Initialize-ServerSession')) 'no Initialize-ServerSession between bootstrap done and project_menu_shown'
Assert ($readyToMenu -and ($readyToMenu -notmatch 'Step "Server setup"')) 'no Server setup Step before project_menu_shown'

$menuToPick = [regex]::Match($connect, '(?s)INTERACTIVE: project_menu_shown[\s\S]*?Wait-DeferredServerSetup').Value
Assert ($menuToPick -and ($menuToPick -match 'Start-DeferredServerSetup')) 'background setup starts after project_menu_shown'
Assert ($menuToPick -and ($menuToPick -match 'Choose-Project')) 'Choose-Project runs while deferred setup may overlap'

$postPick = [regex]::Match($connect, '(?s)Wait-DeferredServerSetup[\s\S]*?Initialize-SessionBgTunnel').Value
Assert ($postPick -and ($postPick -match 'Wait-DeferredServerSetup')) 'Wait-DeferredServerSetup runs before tunnel init path'

$initFn = Get-FunctionSource -Source $connect -Name 'Initialize-ServerSession'
Assert (($initFn -match 'Ensure-LaptopSshReady') -and ($initFn -match '\$script:LaptopFirewallOk\s*=\s*\$true')) 'Ensure#1 hard-fail preserved in Initialize-ServerSession'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All Task 8 deferred setup tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
