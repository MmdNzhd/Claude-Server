# Deep local audit: Desktop/Temp Claude-Connect layout + recent update health
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0; $warn = 0
function Ok($m) { $script:pass++; Write-Host "PASS  $m" -ForegroundColor Green }
function Bad($m) { $script:fail++; Write-Host "FAIL  $m" -ForegroundColor Red }
function Warn($m) { $script:warn++; Write-Host "WARN  $m" -ForegroundColor Yellow }

Write-Host '=== LOCAL DEEP AUDIT ===' -ForegroundColor Cyan

# stamps
$stamp = Join-Path $env:USERPROFILE '.config\claude-connect\last-launch-dir.txt'
if (Test-Path $stamp) {
    $sd = (Get-Content $stamp -Raw).Trim()
    Write-Host "stamp=$sd"
    $leaf = Split-Path -Leaf $sd
    if ($leaf -match '^\d{8}\.\d+$') {
        $root = Split-Path -Parent $sd
        $curF = Join-Path $root 'current.txt'
        if (Test-Path $curF) {
            $cur = (Get-Content $curF -Raw).Trim()
            if ($leaf -eq $cur) { Ok "last-launch-dir matches current.txt ($cur)" }
            else { Bad "last-launch-dir leaf=$leaf but current.txt=$cur" }
        } else { Warn 'current.txt missing next to stamp VerDir' }
    } else { Warn "last-launch-dir not a VerDir: $sd" }
} else { Warn 'last-launch-dir.txt missing' }

function Audit-ConnectRoot([string]$Root, [string]$Label) {
    Write-Host "--- $Label : $Root ---" -ForegroundColor Cyan
    if (-not (Test-Path $Root)) { Warn "$Label missing"; return }
    $curF = Join-Path $Root 'current.txt'
    $flatPs1 = Test-Path (Join-Path $Root 'connect.ps1')
    $verDirs = @(Get-ChildItem $Root -Directory -EA SilentlyContinue | Where-Object { $_.Name -match '^\d{8}\.\d+$' })
    if (Test-Path $curF) {
        $cur = (Get-Content $curF -Raw).Trim()
        Ok "$Label current.txt=$cur"
        $src = Join-Path (Join-Path $Root $cur) 'src\connect.ps1'
        if (Test-Path $src) { Ok "$Label current src has connect.ps1" } else { Bad "$Label current src missing connect.ps1" }
        $vf = Join-Path (Join-Path $Root $cur) 'src\connect-version.txt'
        if (Test-Path $vf) {
            $vv = (Get-Content $vf -Raw).Trim()
            if ($vv -eq $cur) { Ok "$Label src version matches folder ($vv)" } else { Bad "$Label src version=$vv folder=$cur" }
        }
        $exe = Join-Path (Join-Path $Root $cur) ("Claude-Connect-{0}.exe" -f $cur)
        if (Test-Path $exe) { Ok "$Label versioned EXE present" } else { Warn "$Label versioned EXE missing: $exe" }
    } else {
        if ($flatPs1) { Warn "$Label flat root (no current.txt)" } else { Warn "$Label no current.txt and no flat connect.ps1" }
    }
    if ($flatPs1 -and (Test-Path $curF)) { Warn "$Label HYBRID: flat connect.ps1 still at root + versioned current.txt" }
    elseif (-not $flatPs1 -and (Test-Path $curF)) { Ok "$Label root has no orphan connect.ps1" }

    foreach ($d in $verDirs) {
        $foreign = @(Get-ChildItem $d.FullName -Filter 'Claude-Connect-*.exe' -File -EA SilentlyContinue |
            Where-Object { $_.BaseName -ne ("Claude-Connect-" + $d.Name) })
        if ($foreign.Count -gt 0) {
            Bad ("$Label foreign EXE in {0}: {1}" -f $d.Name, (($foreign | ForEach-Object Name) -join ', '))
        } else {
            Ok "$Label no foreign EXE in $($d.Name)"
        }
    }
    Write-Host ("  ver_dirs={0}: {1}" -f $verDirs.Count, (($verDirs | ForEach-Object Name) -join ', '))
}

Audit-ConnectRoot (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect') 'Desktop'
Audit-ConnectRoot 'C:\Temp\Claude-Connect' 'TempClaude'
$test = 'C:\Temp\test'
if (Test-Path $test) {
    $kids = @(Get-ChildItem $test -Force)
    Write-Host "--- Temp\\test ---"
    Write-Host ("  entries={0}: {1}" -f $kids.Count, (($kids | ForEach-Object Name) -join ', '))
    if (Test-Path (Join-Path $test 'Claude-Connect')) { Ok 'Temp\test has Claude-Connect tree' }
    else { Warn 'Temp\test has no Claude-Connect tree (EXE-only drop; expected until that EXE is run successfully)' }
}

# recent update log health
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260727.log'
if (Test-Path $log) {
    Write-Host '--- recent UPDATE log ---' -ForegroundColor Cyan
    $lines = Get-Content $log -Tail 400
    $upd = $lines | Where-Object { $_ -match 'UPDATE:' }
    $failLines = @($upd | Where-Object { $_ -match 'checksum_fail|apply_rollback|versioned_apply_fail|UPDATE_EXIT exit=1|checksum failed' })
    $okLines = @($upd | Where-Object { $_ -match 'versioned_apply ok|checksum_ok|applied_ok|up to date|available v' })
    Write-Host ("  update_lines_tail~{0} fails~{1}" -f $upd.Count, $failLines.Count)
    foreach ($x in ($failLines | Select-Object -Last 8)) { Write-Host "  $x" -ForegroundColor Yellow }
    $lastApply = @($upd | Where-Object { $_ -match 'versioned_apply ok|checksum_ok|checksum_fail|applied_ok' } | Select-Object -Last 5)
    foreach ($x in $lastApply) { Write-Host "  $x" }
    if ($failLines.Count -eq 0) { Ok 'no checksum/apply fails in last 400 log lines UPDATE' }
    else {
        $recentFail = @($failLines | Where-Object { $_ -match '17:1[5-9]|17:2|18:' })
        if ($recentFail.Count -gt 0) { Bad 'recent UPDATE failures present (see WARN lines)' }
        else { Warn 'older UPDATE failures in tail window (may be pre-fix)' }
    }
    # foreign promote evidence
    $foreignPromo = @($upd | Where-Object { $_ -match 'exe_versioned_promoted.*20260727\.17\\Claude-Connect-20260727\.2' })
    if ($foreignPromo.Count -gt 0) { Warn ("historical foreign promote into .17 seen x{0}" -f $foreignPromo.Count) }
    $skipForeign = @($upd | Where-Object { $_ -match 'exe_versioned_skip foreign_verdir' })
    if ($skipForeign.Count -gt 0) { Ok ("foreign_verdir skip logged x{0}" -f $skipForeign.Count) }
} else { Warn 'day log missing' }

# critical local tests
Write-Host '--- LIVE regression tests ---' -ForegroundColor Cyan
$tests = @(
    'test-boot-flat-migrate-live.ps1',
    'test-flat-update-creates-verdir-live.ps1'
)
$td = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($t in $tests) {
    $p = Join-Path $td $t
    $r = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p 2>&1
    $tail = ($r | Select-Object -Last 3) -join ' | '
    if ($LASTEXITCODE -eq 0) { Ok "$t exit=0 ($tail)" } else { Bad "$t exit=$LASTEXITCODE ($tail)" }
}

Write-Host ("=== LOCAL RESULT pass={0} fail={1} warn={2} ===" -f $pass, $fail, $warn)
if ($fail -gt 0) { exit 1 }
exit 0
