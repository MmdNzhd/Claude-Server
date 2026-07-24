# test-sshx-hard-kill-live.ps1 - #P3 LIVE: Invoke-SshXCore must actually kill a genuinely
# hung child process within its hard-kill ceiling and leave zero orphan, exercising the real
# function body against a real (compiled stub) executable - not a source-pattern check.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== SSH client hard-kill #P3 (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$src = Get-FunctionSource -Content $content -Name 'Invoke-SshXCore'
if (-not $src) {
    Write-Host '  FAIL  could not extract Invoke-SshXCore source - live test cannot run (source drifted)' -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($src))

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-p3-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$pidFile = Join-Path $tmp 'stub.pid'
$stubExe = Join-Path $tmp 'ssh.exe'
$stubSrc = @'
using System;
using System.IO;
using System.Threading;
class SshStubHang {
    static void Main(string[] args) {
        try {
            var f = Environment.GetEnvironmentVariable("CC_STUB_PIDFILE");
            if (!string.IsNullOrEmpty(f)) {
                File.WriteAllText(f, System.Diagnostics.Process.GetCurrentProcess().Id.ToString());
            }
        } catch { }
        Thread.Sleep(Timeout.Infinite);
    }
}
'@
try {
    Add-Type -Language CSharp -TypeDefinition $stubSrc -OutputType ConsoleApplication -OutputAssembly $stubExe -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile hang-stub ssh.exe: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Assert (Test-Path -LiteralPath $stubExe) 'stub hang-forever ssh.exe compiled to a real binary'

$origPath = $env:PATH
$origPidFileEnv = $env:CC_STUB_PIDFILE
$env:PATH = "$tmp;$origPath"
$env:CC_STUB_PIDFILE = $pidFile
$script:SshXCoreHardKillMs = 2500
$script:ConnectSshExtraOptions = @()
$Alias = 'unit-test-alias'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = Invoke-SshXCore -RemoteCmd 'echo should_never_run'
$sw.Stop()

$env:PATH = $origPath
$env:CC_STUB_PIDFILE = $origPidFileEnv

Assert ($result.Exit -eq 124) "returned sentinel exit=124 on hard-kill (got $($result.Exit))"
Assert ($sw.ElapsedMilliseconds -lt 8000) "wall-clock bounded well under old unbounded-hang risk (got $($sw.ElapsedMilliseconds)ms, ceiling was 2500ms)"
Assert ($sw.ElapsedMilliseconds -ge 2000) "did not return suspiciously early / before the ceiling had a real chance to fire (got $($sw.ElapsedMilliseconds)ms)"

$stubPid = 0
$sawStub = (Test-Path -LiteralPath $pidFile) -and [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue), [ref]$stubPid)
Assert $sawStub 'hang-stub process actually started and ran (proves this exercised a real child process, not a mock)'
if ($sawStub) {
    Start-Sleep -Milliseconds 300
    $stillAlive = $false
    try { $stillAlive = [bool](Get-Process -Id $stubPid -ErrorAction SilentlyContinue) } catch { $stillAlive = $false }
    Assert (-not $stillAlive) "hard-killed child pid=$stubPid is actually gone (no orphaned hung ssh.exe left behind)"
    if ($stillAlive) { try { Stop-Process -Id $stubPid -Force -ErrorAction SilentlyContinue } catch { } }
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
