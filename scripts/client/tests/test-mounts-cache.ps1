# test-mounts-cache.ps1 - project-list local cache correctness
# Callers: scripts/client/tests/run-all.ps1
# Guards the 2026-07-25 regression where Get-MountsCached collapsed a 16-project catalog into a
# single garbled row. Root cause: PowerShell 5.1's ConvertFrom-Json emits a JSON array as ONE
# non-enumerated pipeline object, so `@($raw | ConvertFrom-Json)` yields a 1-element array whose
# member is the whole 16-object array (properties then flatten to space-joined strings). The fix
# assigns the parse result to a variable FIRST, then wraps with @(). This test exercises the real
# Get-MountsCached / Get-MountsCachePath bodies extracted from windows/connect.ps1.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Mounts cache round-trip ===' -ForegroundColor Cyan
Write-Host ''

$src = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

# --- Source-level guards -------------------------------------------------------------------
Assert ($src -match 'function Get-MountsCached')      'Get-MountsCached defined'
Assert ($src -match 'function Get-MountsCachePath')   'Get-MountsCachePath defined'
Assert ($src -match '\$parsed\s*=\s*\$raw\s*\|\s*ConvertFrom-Json') 'read assigns parse result before wrapping (PS5.1 unroll-safe)'
Assert (-not ($src -match '@\(\s*\$raw\s*\|\s*ConvertFrom-Json\s*\)')) 'read does NOT use buggy @($raw | ConvertFrom-Json)'
Assert ($src -match 'ConvertTo-Json -Depth 4')        'Get-Mounts write-through serializes cache'
Assert ($src -match 'Get-MountsCached')               'menu load path uses Get-MountsCached'

# --- Functional round-trip using the REAL extracted functions ------------------------------
$fnPath   = Get-FunctionSource -Content $src -Name 'Get-MountsCachePath'
$fnCached = Get-FunctionSource -Content $src -Name 'Get-MountsCached'
Assert ($fnPath)   'extracted Get-MountsCachePath body'
Assert ($fnCached) 'extracted Get-MountsCached body'

# Stub so the cache-miss fallback (return @(Get-Mounts)) is safe if ever reached in this harness.
function Get-Mounts { return @() }
. ([ScriptBlock]::Create($fnPath))
. ([ScriptBlock]::Create($fnCached))

$tmpDir = Join-Path $env:TEMP ("mounts-cache-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$script:CfgDir = $tmpDir
try {
    # Build 16 projects and persist exactly like Get-Mounts write-through does.
    $out = @()
    1..16 | ForEach-Object {
        $out += [PSCustomObject]@{
            Id = "id$_"; Label = "Label $_"; Rpath = "R$_"; Lpath = "L$_"
            Path = "P$_"; Active = ($_ -eq 1); Mounted = ($_ -le 3)
        }
    }
    (@($out) | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Get-MountsCachePath) -Encoding UTF8

    $loaded = @(Get-MountsCached)
    Assert ($loaded.Count -eq 16) "cache round-trip preserves 16 projects (got $($loaded.Count))"
    Assert ($loaded[0].Id -eq 'id1' -and $loaded[15].Id -eq 'id16') 'first/last ids intact after round-trip'
    Assert ($loaded[5].Label -eq 'Label 6') 'label is a scalar, not array-joined'
    Assert ($loaded[0].Active -eq $true -and $loaded[1].Active -eq $false) 'boolean fields survive round-trip'

    # Document the exact PS5.1 quirk this fix defends against: the buggy pattern collapses to 1.
    $raw = Get-Content -LiteralPath (Get-MountsCachePath) -Raw
    $buggy = @($raw | ConvertFrom-Json)
    Assert ($buggy.Count -eq 1) 'PS5.1 unroll documented: buggy @($raw|ConvertFrom-Json) collapses to 1'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
