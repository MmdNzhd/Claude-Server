#Requires -Version 5.1
# test-keep-tunnel-marker-hard-batch.ps1 (T2)
# Static asserts: keep-tunnel marker API, UTF8 no-BOM write, atomic rename,
# dead tunnelPid drop, KEEP-before-detach ordering (Win+Mac), sticky <=15m.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Keep-tunnel marker hard batch (T2) ===' -ForegroundColor White

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

# --- API surface ---
Assert ($gm -match 'function Write-ConnectKeepTunnelMarker') 'Write-ConnectKeepTunnelMarker exists'
Assert ($gm -match 'function Clear-ConnectKeepTunnelMarker') 'Clear-ConnectKeepTunnelMarker exists'
Assert ($gm -match 'function Get-ConnectKeepTunnelMarkers') 'Get-ConnectKeepTunnelMarkers exists'
Assert ($gm -match 'function Get-ConnectKeepTunnelMarkerPath') 'Get-ConnectKeepTunnelMarkerPath exists'
Assert ($gm -match 'function Test-ConnectKeepEditorProtect') 'Test-ConnectKeepEditorProtect exists'

# --- Path uses keep-tunnel-{port}.json ---
Assert ($gm -match 'keep-tunnel-\{0\}\.json|keep-tunnel-\$\{?port') 'Get-ConnectKeepTunnelMarkerPath uses keep-tunnel-{port}.json'
Assert ($gm -match 'keep-tunnel-\{0\}\.json') 'Win path format keep-tunnel-{0}.json'

# --- Write: UTF8Encoding($false) / WriteAllText (no BOM Set-Content) ---
Assert ($gm -match 'WriteAllText\(') 'Write uses WriteAllText'
Assert ($gm -match 'UTF8Encoding::new\(\$false\)|UTF8Encoding\]::new\(\$false\)') 'Write uses UTF8Encoding(false) no BOM'
$writeFn = [regex]::Match($gm, '(?s)function Write-ConnectKeepTunnelMarker\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
Assert ($writeFn.Success) 'Write-ConnectKeepTunnelMarker body extractable'
if ($writeFn.Success) {
    Assert ($writeFn.Value -notmatch 'Set-Content') 'Write does not use Set-Content (BOM risk)'
    Assert ($writeFn.Value -match 'WriteAllText') 'Write body uses WriteAllText'
}

# --- Atomic temp + rename (Replace or Move) ---
Assert ($gm -match '\[System\.IO\.File\]::Replace\(') 'Atomic write uses File.Replace'
Assert ($gm -match '\[System\.IO\.File\]::Move\(') 'Atomic write uses File.Move fallback'
Assert ($gm -match '\.write\.\$PID|\.tmp') 'Write uses temp file before rename'

# --- Get drops dead tunnelPid ---
Assert ($gm -match 'dead_tunnelPid|reason=dead_tunnelPid') 'Get drops dead tunnelPid markers'
Assert ($gm -match 'Get-Process -Id \$tunnelPid') 'Get checks tunnelPid process liveness'

# --- connect.ps1: Write BEFORE Detach in KEEP finally ---
$idxWrite = $connect.IndexOf('Write-ConnectKeepTunnelMarker')
$idxDetach = $connect.IndexOf('Detach-CursorProxySidecarJobProcess')
Assert ($idxWrite -ge 0) 'connect.ps1 has Write-ConnectKeepTunnelMarker'
Assert ($idxDetach -ge 0) 'connect.ps1 has Detach-CursorProxySidecarJobProcess'
Assert (($idxWrite -ge 0) -and ($idxDetach -ge 0) -and ($idxWrite -lt $idxDetach)) `
    'Write-ConnectKeepTunnelMarker appears BEFORE Detach-CursorProxySidecarJobProcess (KEEP finally)'

# --- Mac: write_connect_keep_tunnel_marker before disown ---
$idxMacWrite = $mac.IndexOf('write_connect_keep_tunnel_marker')
# Prefer the KEEP finally call site: search near FINALLY_KEEP (avoid comment "BEFORE disown")
$keepBlock = [regex]::Match($mac, '(?s)FINALLY_KEEP_TUNNEL.*?\[ -n "\$\{bg_pid:-\}" \] && disown')
Assert ($keepBlock.Success) 'Mac FINALLY_KEEP block with disown found'
if ($keepBlock.Success) {
    $blk = $keepBlock.Value
    $w = $blk.IndexOf('write_connect_keep_tunnel_marker')
    $d = $blk.LastIndexOf('disown')
    Assert (($w -ge 0) -and ($d -ge 0) -and ($w -lt $d)) `
        'Mac write_connect_keep_tunnel_marker before disown (index in KEEP block)'
}
Assert ($idxMacWrite -ge 0) 'Mac connect.sh calls write_connect_keep_tunnel_marker'
Assert ($gmSh -match 'write_connect_keep_tunnel_marker') 'Mac git-mode.sh defines write_connect_keep_tunnel_marker'

# --- sticky <=15m in Test-ConnectKeepEditorProtect ---
Assert ($gm -match 'ageMin\s*-le\s*15|TotalMinutes.*15|-le 15') 'Test-ConnectKeepEditorProtect sticky <=15m'
Assert ($gm -match 'KEEP_PROTECT sticky=1') 'KEEP_PROTECT sticky log present'
Assert ($gmSh -match 'age_min.*-le 15|\[ "\$age_min" -le 15 \]') 'Mac sticky <=15m'

# --- Soft mount_only + dead-bound parity hooks (smoke) ---
Assert ($gm -match 'mount_only_down') 'Win Soft mount_only_down'
Assert ($gm -match 'Invoke-ConnectMountDownDeadBoundPorts|HYGIENE_SOFT_DEAD_BOUND') 'Win Soft dead-bound heal'
Assert ($gmSh -match 'mount_only_down') 'Mac Soft mount_only_down'
Assert ($gmSh -match 'invoke_connect_mount_down_dead_bound_ports|HYGIENE_SOFT_DEAD_BOUND') 'Mac Soft dead-bound heal'

Write-Host ''
if ($failed -eq 0) { Write-Host "All $passed assertions passed." -ForegroundColor Green; exit 0 }
Write-Host "$failed failed / $passed passed." -ForegroundColor Red; exit 1
