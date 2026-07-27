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
    Assert (-not (Test-Path (Join-Path $flat 'connect.ps1'))) 'root no longer has connect.ps1'
    Assert ((Get-Content (Join-Path $flat 'current.txt') -Raw).Trim() -eq '20990103.01') 'current.txt set'
    Assert (Test-Path (Join-Path $flat 'connect.bat')) 'root redirect stub connect.bat present'
    $stub = Get-Content (Join-Path $flat 'connect.bat') -Raw
    Assert ($stub -match 'current\.txt' -and $stub -match 'VER!\\src' -and $stub -match 'connect\.bat') 'stub redirects via current.txt to src\connect.bat'

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
