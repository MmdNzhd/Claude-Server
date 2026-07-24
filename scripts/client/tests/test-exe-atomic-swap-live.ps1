# test-exe-atomic-swap-live.ps1 - #P6 LIVE: Copy-ExeAtomicSwap must actually succeed at
# overwriting a Destination file while a real process is running/mapped from it - the exact
# failure Windows produces against a plain Copy-Item -Force - and the already-running process
# instance must survive unaffected.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== EXE atomic rename-swap #P6 (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
foreach ($n in @('Get-SafeFileSha256', 'Copy-ExeAtomicSwap')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}
function Write-UpdateFileLog { param([string]$Msg, [string]$Level = 'INFO') }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-p6-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function New-SleepStubExe {
    param([string]$Path, [string]$Marker)
    $src = @"
using System.Threading;
class Stub_$Marker {
    static void Main(string[] args) { Thread.Sleep(Timeout.Infinite); }
}
"@
    Add-Type -Language CSharp -TypeDefinition $src -OutputType ConsoleApplication -OutputAssembly $Path -ErrorAction Stop
}

$runningExe = Join-Path $tmp 'Claude-Connect.exe'
$newBuildExe = Join-Path $tmp 'new-build.exe'
$proc = $null
try {
    New-SleepStubExe -Path $runningExe -Marker 'Old'
    New-SleepStubExe -Path $newBuildExe -Marker 'New'
    $oldHash = Get-SafeFileSha256 -Path $runningExe
    $newHash = Get-SafeFileSha256 -Path $newBuildExe
    Assert ($oldHash -and $newHash -and $oldHash -ne $newHash) 'old/new stub builds have distinct real SHA256 hashes (content genuinely differs, not a no-op)'

    $proc = Start-Process -FilePath $runningExe -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 400
    Assert (-not $proc.HasExited) 'the "currently installed" exe is actually running/mapped, matching the real bug scenario'

    $plainCopyDenied = $false
    try { Copy-Item -LiteralPath $newBuildExe -Destination $runningExe -Force -ErrorAction Stop }
    catch { $plainCopyDenied = $true }
    Assert $plainCopyDenied 'a plain Copy-Item -Force is genuinely denied by Windows while the exe is running (reproduces the original #P6 bug precondition)'
    Assert (-not $proc.HasExited) 'the running process survived the denied plain-copy attempt'

    $swapOk = Copy-ExeAtomicSwap -Source $newBuildExe -Destination $runningExe
    Assert $swapOk 'Copy-ExeAtomicSwap reports success while the destination is locked/running'
    Assert (-not $proc.HasExited) 'the ALREADY-RUNNING process instance is unaffected by the rename-swap (FILE_SHARE_DELETE semantics hold)'

    $afterHash = Get-SafeFileSha256 -Path $runningExe
    Assert ($afterHash -eq $newHash) 'the file now on disk at the destination path really is the new build (hash matches new build, not old)'

    $oldLeftovers = @(Get-ChildItem -LiteralPath $tmp -Filter '*.old-*' -ErrorAction SilentlyContinue)
    Assert ($oldLeftovers.Count -le 1) "at most one .old- artifact left behind (best-effort cleanup attempted; found $($oldLeftovers.Count))"

    $swapOk2 = Copy-ExeAtomicSwap -Source $newBuildExe -Destination $runningExe
    Assert $swapOk2 'calling the swap again with already-identical content still reports success (identical-content skip path)'
    Assert (-not $proc.HasExited) 'process still unaffected after the second (no-op) swap call'
} finally {
    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch { }
        try { [void]$proc.WaitForExit(3000) } catch { }
    }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
