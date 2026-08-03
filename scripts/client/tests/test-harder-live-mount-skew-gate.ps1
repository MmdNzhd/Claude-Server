#Requires -Version 5.1
# test-harder-live-mount-skew-gate.ps1 (L7)
# Static extract of _mount_skew_keep_fuse via regex on claude-mount.sh:
# DEFERRED return 0; ALIGN calls _align; SKEW return 1; never fusermount in ALIGN branch.
# Honest SKIP only if file missing.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARDER LIVE L7: mount skew gate (_mount_skew_keep_fuse) ===' -ForegroundColor Cyan

$mountPath = Get-ServerFile 'server\claude-mount.sh'
if (-not (Test-Path -LiteralPath $mountPath)) {
    Write-Host ("SKIPPED: claude-mount.sh missing at {0}" -f $mountPath) -ForegroundColor Yellow
    $Skip++
    Write-Host ("L7 mount-skew-gate RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

$mount = Get-Content -LiteralPath $mountPath -Raw
Assert ($mount -match '_mount_skew_keep_fuse') 'claude-mount defines _mount_skew_keep_fuse'

$skewFn = ''
if ($mount -match '(?s)_mount_skew_keep_fuse\(\)\s*\{(.{200,8000}?)(?:\n_do_unmount|\n_force_unmount|\n# Try every|\n[a-z_]+\(\)\s*\{)') {
    $skewFn = $Matches[1]
}
# Fallback: brace-depth extract from function name
if (-not $skewFn) {
    $m = [regex]::Match($mount, '_mount_skew_keep_fuse\(\)\s*\{')
    if ($m.Success) {
        $i = $m.Index + $m.Length - 1
        $depth = 0
        for ($j = $i; $j -lt $mount.Length; $j++) {
            if ($mount[$j] -eq '{') { $depth++ }
            elseif ($mount[$j] -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $skewFn = $mount.Substring($m.Index, $j - $m.Index + 1)
                    break
                }
            }
        }
    }
}
Assert ([bool]$skewFn) 'extracted _mount_skew_keep_fuse body'

if ($skewFn) {
    # DEFERRED: both tunnels live → return 0 (keep FUSE)
    Assert ($skewFn -match 'MOUNT_PORT_SKEW_DEFERRED') 'DEFERRED log present'
    Assert ($skewFn -match '(?s)MOUNT_PORT_SKEW_DEFERRED[\s\S]{0,200}return 0') `
        'DEFERRED path returns 0 (keep FUSE)'

    # ALIGN: calls _align_conf_tunnel_to_live; return 0; never fusermount in this function
    Assert ($skewFn -match 'MOUNT_PORT_SKEW_ALIGN') 'ALIGN log present'
    Assert ($skewFn -match '_align_conf_tunnel_to_live') 'ALIGN calls _align_conf_tunnel_to_live'

    # Isolate ALIGN branch: from ALIGN log to next return / end of conf-down arm
    $alignIdx = $skewFn.IndexOf('MOUNT_PORT_SKEW_ALIGN')
    Assert ($alignIdx -ge 0) 'ALIGN index found'
    if ($alignIdx -ge 0) {
        $alignTail = $skewFn.Substring($alignIdx)
        # ALIGN branch must call _align and return 0 without fusermount
        Assert ($alignTail -match '_align_conf_tunnel_to_live') 'ALIGN tail calls _align'
        Assert ($alignTail -match 'return 0') 'ALIGN branch returns 0'
        Assert ($alignTail -notmatch 'fusermount') 'ALIGN branch never calls fusermount'
    }

    # Whole keep_fuse fn: no fusermount *invocation* (comment may say "never fusermount")
    Assert ($skewFn -notmatch '(?m)^\s*fusermount') `
        '_mount_skew_keep_fuse never invokes fusermount (ALIGN or otherwise)'

    # SKEW remount signal: return 1
    Assert ($skewFn -match 'MOUNT_PORT_SKEW[^_]') 'SKEW (remount) log present'
    Assert ($skewFn -match '(?s)MOUNT_PORT_SKEW lpath=[\s\S]{0,300}return 1|MOUNT_PORT_SKEW[\s\S]{0,200}\(remount\)[\s\S]{0,80}return 1') `
        'SKEW path returns 1 (caller remounts)'
}

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L7 mount-skew-gate RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
