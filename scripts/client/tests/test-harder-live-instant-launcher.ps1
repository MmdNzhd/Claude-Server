#Requires -Version 5.1
# test-harder-live-instant-launcher.ps1
#
# LIVE harder gate (~14 Assert calls) for Write-ConnectInstantLauncher extracted verbatim
# from publish\_setup-launch-body.ps1. Exercises spaced VerDir paths, triple rapid .cmd
# launches, orphan cmd proof, VBS direct boot, and static fail-closed patterns.
# Does NOT modify run-all.ps1 or production scripts.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

$SelfPath = $MyInvocation.MyCommand.Path
Write-Host ''
Write-Host '=== HARDER LIVE: instant launcher (Write-ConnectInstantLauncher) ===' -ForegroundColor White
Write-Host ("  test={0}" -f $SelfPath) -ForegroundColor DarkGray
Write-Host ''

$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$launchSrc = Get-Content -LiteralPath $launchPath -Raw

# ---------------------------------------------------------------------------
# Extract REAL Write-ConnectInstantLauncher (not reimplemented)
# ---------------------------------------------------------------------------
Note 'extract Write-ConnectInstantLauncher from publish body'
$instantFn = Get-FunctionSource -Content $launchSrc -Name 'Write-ConnectInstantLauncher'
Assert ($null -ne $instantFn) 'extracted Write-ConnectInstantLauncher from publish body'
Assert ($instantFn -match 'Claude-Connect\.vbs') 'function writes Claude-Connect.vbs'
Assert ($instantFn -match 'Claude-Connect\.cmd') 'function writes Claude-Connect.cmd trampoline'
Assert ($instantFn -notmatch 'start "Claude Connect" /D') `
    'function must not use start "Claude Connect" /D powershell (orphan cmd)'
Assert ($instantFn -match 'exit /b 0') 'function cmd trampoline declares exit /b 0'
Assert ($instantFn -match 'MsgBox "Missing connect-boot\.ps1') `
    'VBS static path shows MsgBox when connect-boot.ps1 missing'

$lc = New-Object System.Text.StringBuilder
[void]$lc.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$lc.AppendLine('function Log([string]$m) { }')
[void]$lc.AppendLine($instantFn)
Invoke-Expression $lc.ToString()

# Spaced VerDir — adversarial path class used by sibling harder tests
$root = Join-Path $env:TEMP ("test for update cc-instant-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$verDir = Join-Path $root 'instant ver dir'
$srcDir = Join-Path $verDir 'src'
$marker = Join-Path $root 'boot-count.txt'
Write-Host ("  verdir={0}" -f $verDir) -ForegroundColor DarkGray

try {
    Note 'LIVE spaced VerDir: stub connect-boot + launcher files'
    $null = New-Item -ItemType Directory -Force -Path $srcDir
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

    $bootBody = @"
`$ErrorActionPreference = 'Stop'
`$f = '$($marker -replace "'", "''")'
`$n = 0
if (Test-Path -LiteralPath `$f) { try { `$n = [int](Get-Content -LiteralPath `$f -Raw).Trim() } catch { `$n = 0 } }
Set-Content -LiteralPath `$f -Value ([string](`$n + 1)) -Encoding ASCII
Start-Sleep -Milliseconds 600
"@
    Set-Content -LiteralPath (Join-Path $srcDir 'connect-boot.ps1') -Value $bootBody -Encoding ASCII

    Write-ConnectInstantLauncher -VerDir $verDir -SrcDir $srcDir
    $vbs = Join-Path $verDir 'Claude-Connect.vbs'
    $cmd = Join-Path $verDir 'Claude-Connect.cmd'

    Assert (Test-Path -LiteralPath $vbs) 'LIVE wrote Claude-Connect.vbs under spaced VerDir'
    Assert (Test-Path -LiteralPath $cmd) 'LIVE wrote Claude-Connect.cmd under spaced VerDir'

    $cmdText = Get-Content -LiteralPath $cmd -Raw
    $vbsText = Get-Content -LiteralPath $vbs -Raw
    Assert ($cmdText -match 'wscript\.exe //B //Nologo') 'cmd hands off to wscript //B //Nologo'
    Assert ($vbsText -match 'sh\.Run') 'VBS uses WScript.Shell.Run for connect-boot'

    Note 'LIVE cmd /c trampoline exit code'
    & "$env:SystemRoot\System32\cmd.exe" /d /c "`"$cmd`""
    Assert ($LASTEXITCODE -eq 0) 'cmd /c Claude-Connect.cmd returns exit code 0'

    Note 'LIVE triple rapid cmd /c launcher (Explorer-equivalent)'
    1..3 | ForEach-Object {
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @(
            '/d', '/c', "`"$cmd`""
        ) -WorkingDirectory $verDir -WindowStyle Normal | Out-Null
        Start-Sleep -Milliseconds 80
    }

    $deadline = [datetime]::UtcNow.AddSeconds(12)
    $count = 0
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $marker) {
            try { $count = [int](Get-Content -LiteralPath $marker -Raw).Trim() } catch { $count = 0 }
            if ($count -ge 3) { break }
        }
        Start-Sleep -Milliseconds 150
    }
    Assert ($count -ge 3) ("triple rapid cmd launch booted >=3 times (got $count)")

    Start-Sleep -Milliseconds 1000
    $orphans = @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        $cl -and ($cl -match [regex]::Escape($cmd))
    })
    Assert ($orphans.Count -eq 0) ("zero orphan cmd hosting Claude-Connect.cmd after 1s (got $($orphans.Count))")
    foreach ($o in $orphans) {
        Write-Host ("         orphan pid=$($o.ProcessId) cl=$($o.CommandLine)") -ForegroundColor DarkYellow
        try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }

    Note 'LIVE VBS direct launch boots marker'
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList @(
        '//B', '//Nologo', "`"$vbs`""
    ) -WorkingDirectory $verDir -WindowStyle Hidden | Out-Null

    $deadlineVbs = [datetime]::UtcNow.AddSeconds(8)
    $bootOk = $false
    while ([datetime]::UtcNow -lt $deadlineVbs) {
        if (Test-Path -LiteralPath $marker) { $bootOk = $true; break }
        Start-Sleep -Milliseconds 150
    }
    Assert $bootOk 'VBS direct launch boots connect-boot (marker written)'

} catch {
    Write-Host ("  FAIL  instant launcher live exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($srcDir))
    } | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
Write-Host ("HARDER LIVE INSTANT LAUNCHER: path={0}" -f $SelfPath) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -eq 0) {
    Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Green
    exit 0
}
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
exit 1
