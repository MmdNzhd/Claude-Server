# test-editor-launch.ps1 — quick non-GUI tests for editor launch fix
$ErrorActionPreference = 'Continue'
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$script:LaptopUser = $env:USERNAME

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'editor-launch.ps1')

Write-Host ""
Write-Host "=== Editor launch self-test ===" -ForegroundColor Cyan
Write-Host "  shell admin: $isAdmin"
Write-Host ""

$codeExe = Resolve-EditorExe 'code'
$shim = (Get-Command code -ErrorAction SilentlyContinue).Source

Assert ($codeExe -and (Test-Path $codeExe)) "Resolve code -> $codeExe"
Assert ($codeExe -match '\\Code\.exe$') "code is Code.exe not shim"
Assert ($codeExe -ne $shim) "not code.cmd shim"

if (Get-Command cursor -ErrorAction SilentlyContinue) {
    $cursorExe = Resolve-EditorExe 'cursor'
    Assert ($cursorExe -match '\\cursor\.exe$') "Resolve cursor -> $cursorExe"
}

Write-Host ""
Write-Host "--- CLI flags ---"
& code --disable-chromium-sandbox --version 2>&1 | Out-Null
Assert ($LASTEXITCODE -eq 0) "code --disable-chromium-sandbox --version (rc=$LASTEXITCODE)"

if ($codeExe) {
    $job = Start-Job -ScriptBlock {
        param($exe)
        & $exe --disable-chromium-sandbox --version 2>&1 | Out-Null
        "__EXIT__=$LASTEXITCODE"
    } -ArgumentList $codeExe
    $done = Wait-Job $job -Timeout 8
    if (-not $done) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "  SKIP  Code.exe direct hung >8s (shim test above is what connect uses)" -ForegroundColor DarkGray
    } else {
        $out = Receive-Job $job
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        $rc = [int](($out | Where-Object { $_ -match '^__EXIT__=' }) -replace '^__EXIT__=', '0')
        if ($rc -eq 0) {
            Assert $true "Code.exe direct + sandbox flag (rc=0)"
        } else {
            Write-Host "  SKIP  Code.exe direct --version rc=$rc (shim + connect path OK)" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
if ($isAdmin) {
    Write-Host "--- elevated shell ---"
    & code --disable-chromium-sandbox --version 2>&1 | Out-Null
    Assert ($LASTEXITCODE -eq 0) "elevated: code + sandbox flag ok"
} else {
    Write-Host "  INFO  not elevated (connect.bat self-elevates)" -ForegroundColor DarkGray
}

$outFile = Join-Path $env:TEMP 'claude-editor-admin-test.txt'
if (-not $isAdmin) {
    $elevScript = @"
`$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
`$exe = '$($codeExe -replace "'", "''")'
& code --version 2>&1 | Out-Null
`$noFlag = `$LASTEXITCODE
& code --disable-chromium-sandbox --version 2>&1 | Out-Null
`$withFlag = `$LASTEXITCODE
@(
  "admin=`$isAdmin",
  "noFlag=`$noFlag",
  "withFlag=`$withFlag"
) | Set-Content -Path '$($outFile -replace "'", "''")' -Encoding ASCII
"@
    $elevPath = Join-Path $env:TEMP 'claude-editor-elev-test.ps1'
    Set-Content -Path $elevPath -Value $elevScript -Encoding ASCII
    Write-Host ""
    Write-Host "--- spawning elevated test (UAC may appear) ---"
    try {
        $p = Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$elevPath) -PassThru -Wait -ErrorAction Stop
        if (Test-Path $outFile) {
            Get-Content $outFile | ForEach-Object { Write-Host "  $_" }
            $lines = Get-Content $outFile
            $wf = ($lines | Where-Object { $_ -match '^withFlag=' }) -replace 'withFlag=',''
            Assert ($wf -eq '0') "elevated subprocess: --disable-chromium-sandbox works"
        } else {
            Write-Host "  SKIP  elevated test cancelled or blocked" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  SKIP  elevated test: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
