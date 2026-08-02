# LIVE: connect-boot silent flat -> {ver}\src (old users just click Update; relaunch migrates).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

$pass = 0; $fail = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { $script:pass++; Write-Host "PASS  $Name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $Name" -ForegroundColor Red }
}

$bootPath = Get-ClientFile 'windows\connect-boot.ps1'
$bootSrc = Get-Content -LiteralPath $bootPath -Raw
Assert ($bootSrc -match 'Repair-ConnectVersionedLayoutAtBoot') 'boot has Repair-ConnectVersionedLayoutAtBoot'
Assert ($bootSrc -match 'flat_migrated_at_boot') 'boot logs flat_migrated_at_boot'
Assert ($bootSrc -match 'Write-ConnectRootRedirectStub') 'boot writes root redirect stub'

# Production connect-boot.ps1 dot-sources connect-env-repair.ps1 before ever calling
# Repair-ConnectVersionedLayoutAtBoot, so Write-ConnectRootRedirectStub's real targets
# (Repair-ConnectRootLayout / Write-ConnectRootInstantLauncher / Set-ConnectInstallCurrent)
# are always available. Load the same file here so this LIVE test exercises the real
# end-to-end repair, not just the two functions in isolation (Set-ConnectInstallCurrent
# already no-ops the machine-wide install-current.txt write for roots under %TEMP%, so
# this is safe to dot-source from a sandbox).
. (Get-ClientFile 'windows\connect-env-repair.ps1')

$fn = Get-FunctionSource -Content $bootSrc -Name 'Repair-ConnectVersionedLayoutAtBoot'
$stubFn = Get-FunctionSource -Content $bootSrc -Name 'Write-ConnectRootRedirectStub'
Assert ($null -ne $fn) 'extract Repair-ConnectVersionedLayoutAtBoot'
Assert ($null -ne $stubFn) 'extract Write-ConnectRootRedirectStub'
Invoke-Expression ($stubFn + "`n" + $fn)

$sandbox = Join-Path $env:TEMP ("boot-flat-mig-{0}" -f [guid]::NewGuid().ToString('N'))
$flat = Join-Path $sandbox 'Claude-Connect'
New-Item -ItemType Directory -Force -Path $flat | Out-Null
try {
    Set-Content (Join-Path $flat 'connect.ps1') -Value '#flat' -Encoding ASCII
    Set-Content (Join-Path $flat 'connect.bat') -Value '@echo old' -Encoding ASCII
    Set-Content (Join-Path $flat 'connect-boot.ps1') -Value '#boot' -Encoding ASCII
    Set-Content (Join-Path $flat 'connect-version.txt') -Value '20990103.01' -NoNewline -Encoding ASCII
    Set-Content (Join-Path $flat 'connect-update.ps1') -Value '#upd' -Encoding ASCII

    $dest = Repair-ConnectVersionedLayoutAtBoot -StartDir $flat
    $src = Join-Path (Join-Path $flat '20990103.01') 'src'
    Assert ($dest -eq $src) 'migrate returns versioned src path'
    Assert (Test-Path (Join-Path $src 'connect.ps1')) 'scripts landed in src'
    Assert (Test-Path (Join-Path $src 'connect.bat')) 'connect.bat also landed in src (not left/stubbed at root)'
    Assert (-not (Test-Path (Join-Path $flat 'connect.ps1'))) 'root no longer has connect.ps1'
    # HARD contract (Repair-ConnectRootLayout comment + CLAUDE.md "Client Script Invariants":
    # "Root must stay version-folders only. Launcher is Desktop\Claude-Connect.vbs (beside
    # folder)"): once the real repair chain runs (connect-env-repair.ps1 loaded above), the
    # versioned root keeps ZERO files - not even current.txt/connect.bat as a redirect stub.
    # current.txt is filed under Repair-ConnectRootLayout's own "stale" removal list and the
    # real install pointer instead lives in the instant .vbs/.cmd launcher written beside
    # (not inside) the root folder.
    $rootFiles = @(Get-ChildItem -LiteralPath $flat -File -Force -ErrorAction SilentlyContinue)
    Assert ($rootFiles.Count -eq 0) ("root has zero files after full repair (got $($rootFiles.Count): $((($rootFiles | Select-Object -ExpandProperty Name) -join ',')))")
    $vbsPath = Join-Path $sandbox 'Claude-Connect.vbs'
    Assert (Test-Path -LiteralPath $vbsPath) 'instant launcher Claude-Connect.vbs written beside root (not inside it)'
    $vbsText = Get-Content -LiteralPath $vbsPath -Raw
    Assert ($vbsText -match [regex]::Escape('20990103.01') -and $vbsText -match 'connect-boot\.ps1') 'launcher references the versioned connect-boot.ps1 path'

    # Already versioned src: noop
    $again = Repair-ConnectVersionedLayoutAtBoot -StartDir $src
    Assert ($again -eq $src) 'versioned src left alone'
}
finally {
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("RESULT pass={0} fail={1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
