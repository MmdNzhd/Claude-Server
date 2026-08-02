# test-pushconf-am-only.ps1 - #17 am_only keeps primary TUNNEL_PORT (T12)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== PushConf am_only / publish_port=0 (static) ===' -ForegroundColor Cyan

$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connectPs1 = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

$push = Get-FunctionSource -Source $gitModePs1 -Name 'Push-ServerConnectConf'
Assert ($push.Length -gt 200) 'Push-ServerConnectConf extracted'
Assert ($push -match 'am_only') 'PushConf mentions am_only'
Assert ($push -match 'publish_port=0') 'PushConf logs publish_port=0 for non-primary'
Assert ($push -match 'AM_ONLY=') 'Remote body sets AM_ONLY'
Assert ($push -match 'CUR_PORT=') 'Remote body reads CUR_PORT'
Assert ($push -match 'PORT_OUT=') 'Remote body uses PORT_OUT'
Assert ($push -match 'port_mismatch_keep') 'Remote body warns port_mismatch_keep'
Assert ($push -notmatch 'skip_non_primary') 'PushConf no longer bare-returns skip_non_primary'
Assert ($push -match 'Test-IsPrimaryTunnelPublisher') 'Still gates on Test-IsPrimaryTunnelPublisher'
Assert ($push -match 'PUSH_CONF_RESULT.*am_only') 'RESULT line includes am_only'
# P1.3: am_only keeps slot preference, but remote body may port_takeover when published is dead.
Assert ($push -match 'port_takeover') 'AM_ONLY body has P1.3 port_takeover liveness override'
Assert ($push -match 'CUR_LIVE') 'AM_ONLY body probes published-port liveness (CUR_LIVE)'

# #18 need_mount TRACE
Assert ($connectPs1 -match "need_mount") 'connect.ps1 mentions need_mount'
Assert ($connectPs1 -match "sshLevel = 'TRACE'") 'SshX demotes expected need_mount to TRACE'

# elevated_direct polish
$el = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($el -match "PROC_START_OK: mode=elevated_direct_fallback' 'DEBUG'") 'elevated_direct OK is DEBUG'
Assert ($el -match "PROC_START_FAIL: mode=elevated_direct_fallback") 'elevated_direct FAIL still logged'

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
