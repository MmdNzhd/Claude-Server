#Requires -Version 5.1
<#
.SYNOPSIS
  Hard battery: UTF-8/mojibake + MCP + pipeline + git-mode + live MCP abuse + optional Smart fleet verify.

.NOTES
  PS 5.1 quirk: Start-Process -PassThru + RedirectStandard* + WaitForExit(ms) leaves ExitCode $null
  even after the process exits. This runner uses a small C# Process helper so exit codes are real.
  Summary lines ("N pass / 0 fail") are a secondary fail signal when fail>0.
#>
param(
    [switch]$SkipLive,
    [switch]$SkipServer,
    [string]$ReportPath = '',
    [string]$ServerHost = 'smart@192.168.210.240'
)

$ErrorActionPreference = 'Stop'
$TestsDir = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $TestsDir '..\..\..')).Path
if (-not $ReportPath) {
    $ReportPath = Join-Path $RepoRoot 'publish\_hard-utf8-mcp-fleet.log'
}

if (-not ('ClaudeConnect.TestProcRunnerV4' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Threading;
using System.Text;

namespace ClaudeConnect {
  public static class TestProcRunnerV4 {
    static void KillTree(int pid) {
      try {
        var psiKill = new ProcessStartInfo {
          FileName = "taskkill.exe",
          Arguments = "/PID " + pid + " /T /F",
          UseShellExecute = false,
          CreateNoWindow = true,
          RedirectStandardOutput = true,
          RedirectStandardError = true
        };
        using (var k = Process.Start(psiKill)) {
          if (k != null) k.WaitForExit(8000);
        }
      } catch { }
    }

    public static int Run(string fileName, string arguments, string workDir, int timeoutMs,
                          out string stdout, out string stderr, out bool timedOut) {
      timedOut = false;
      var so = new StringBuilder();
      var se = new StringBuilder();
      var psi = new ProcessStartInfo {
        FileName = fileName,
        Arguments = arguments,
        WorkingDirectory = string.IsNullOrEmpty(workDir) ? Environment.CurrentDirectory : workDir,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true
      };
      using (var p = new Process()) {
        p.StartInfo = psi;
        p.OutputDataReceived += (s, e) => { if (e.Data != null) so.AppendLine(e.Data); };
        p.ErrorDataReceived += (s, e) => { if (e.Data != null) se.AppendLine(e.Data); };
        p.Start();
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        // Poll HasExited — WaitForExit(ms) can hang forever with redirected async I/O
        // on .NET Framework when child processes inherit console/pipe handles.
        var sw = Stopwatch.StartNew();
        while (!p.HasExited) {
          if (sw.ElapsedMilliseconds > timeoutMs) {
            timedOut = true;
            KillTree(p.Id);
            try { if (!p.HasExited) p.Kill(); } catch { }
            var killWait = Stopwatch.StartNew();
            while (!p.HasExited && killWait.ElapsedMilliseconds < 8000) {
              Thread.Sleep(100);
            }
            Thread.Sleep(300); // brief drain for async handlers
            stdout = so.ToString();
            stderr = se.ToString();
            return 124;
          }
          Thread.Sleep(200);
        }
        // Do NOT call parameterless WaitForExit() — it can hang forever waiting for
        // stdout/stderr EOF when grandchildren still hold inherited pipe handles.
        // HasExited is already true; ExitCode is available; give handlers a short drain.
        Thread.Sleep(400);
        stdout = so.ToString();
        stderr = se.ToString();
        return p.ExitCode;
      }
    }
  }
}
'@
}

function Write-Report([string]$Line) {
    for ($i = 0; $i -lt 8; $i++) {
        try {
            Add-Content -LiteralPath $script:ReportPath -Value $Line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds (80 * ($i + 1))
        }
    }
    # Never fail the battery on report I/O
    try { [IO.File]::AppendAllText($script:ReportPath, $Line + [Environment]::NewLine) } catch { }
}

function Invoke-TestProcess {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [int]$TimeoutSec = 300,
        [string]$Label = ''
    )
    if (-not $Label) { $Label = [IO.Path]::GetFileName($ScriptPath) }

    $stdout = ''
    $stderr = ''
    $timedOut = $false
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    $work = [IO.Path]::GetDirectoryName($ScriptPath)
    $ec = [ClaudeConnect.TestProcRunnerV4]::Run(
        $psExe, $args, $work, [Math]::Max(1000, $TimeoutSec * 1000),
        [ref]$stdout, [ref]$stderr, [ref]$timedOut
    )

    $text = $stdout
    if ($stderr) { $text = $text + "`nSTDERR:`n" + $stderr }

    $passCount = -1
    $failCount = -1
    if ($text -match '(\d+)\s+pass\s*/\s*(\d+)\s+fail') {
        $passCount = [int]$Matches[1]
        $failCount = [int]$Matches[2]
    }

    $ok = (-not $timedOut) -and ($ec -eq 0)
    if ($failCount -gt 0) { $ok = $false }
    if ($text -match '(?m)^ASSERT FAIL:') { $ok = $false; if ($ec -eq 0) { $ec = 1 } }

    return [pscustomobject]@{
        Label     = $Label
        ExitCode  = $ec
        TimedOut  = $timedOut
        Output    = $text
        PassCount = $passCount
        FailCount = $failCount
        Ok        = $ok
    }
}

$suites = @(
    @{ Script = 'test-hard-utf8-mojibake-fleet.ps1'; Timeout = 90; Live = $false }
    @{ Script = 'test-windows-mcp-hard-batch.ps1'; Timeout = 60; Live = $false }
    @{ Script = 'test-windows-mcp-no-orphan-cmd.ps1'; Timeout = 60; Live = $false }
    @{ Script = 'test-connect-pipeline.ps1'; Timeout = 90; Live = $false }
    @{ Script = 'test-git-mode-deep.ps1'; Timeout = 90; Live = $false }
    @{ Script = 'test-hardest-live-windows-mcp-chaos.ps1'; Timeout = 420; Live = $true }
    @{ Script = 'test-harder-live-windows-mcp-storm.ps1'; Timeout = 360; Live = $true }
    @{ Script = 'test-brutal-live-windows-mcp-abuse.ps1'; Timeout = 360; Live = $true }
)

try {
    '' | Set-Content -LiteralPath $ReportPath -Encoding UTF8 -ErrorAction Stop
} catch {
    $ReportPath = Join-Path $RepoRoot ('publish\_hard-utf8-mcp-fleet-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    '' | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
$script:ReportPath = $ReportPath
Write-Host ''
Write-Host '=== HARD UTF-8 / MCP FLEET ===' -ForegroundColor White
Write-Host ("Report: {0}" -f $ReportPath) -ForegroundColor DarkGray
Write-Report ("STARTED {0} SkipLive={1} SkipServer={2}" -f (Get-Date -Format o), [bool]$SkipLive, [bool]$SkipServer)

$fail = 0

foreach ($s in $suites) {
    if ($SkipLive -and $s.Live) {
        Write-Host ("SKIP  {0} (SkipLive)" -f $s.Script) -ForegroundColor Yellow
        Write-Report ("SKIP {0} SkipLive" -f $s.Script)
        continue
    }
    $path = Join-Path $TestsDir $s.Script
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host ("MISS  {0}" -f $s.Script) -ForegroundColor Red
        Write-Report ("MISS {0}" -f $s.Script)
        $fail++
        continue
    }

    $hdr = '===== BEGIN {0} timeout={1}s {2} =====' -f $s.Script, $s.Timeout, (Get-Date -Format o)
    Write-Host $hdr -ForegroundColor Cyan
    Write-Report $hdr

    $r = Invoke-TestProcess -ScriptPath $path -TimeoutSec $s.Timeout -Label $s.Script
    Write-Report $r.Output
    if ($r.TimedOut) {
        Write-Report 'TIMEOUT EXIT=124'
        Write-Host ("TIMEOUT {0}" -f $s.Script) -ForegroundColor Red
        $fail++
        continue
    }
    Write-Report ('EXIT={0}' -f $r.ExitCode)
    if ($r.PassCount -ge 0) {
        Write-Host ('  summary: {0} pass / {1} fail  exit={2}' -f $r.PassCount, $r.FailCount, $r.ExitCode) -ForegroundColor DarkGray
    } else {
        Write-Host ('  exit={0}' -f $r.ExitCode) -ForegroundColor DarkGray
    }
    if ($r.Ok) {
        Write-Host ("PASS  {0}" -f $s.Script) -ForegroundColor Green
    } else {
        Write-Host ("FAIL  {0} EXIT={1}" -f $s.Script, $r.ExitCode) -ForegroundColor Red
        $fail++
    }
}

if (-not $SkipServer) {
    $verifySh = Join-Path $RepoRoot 'publish\_verify-utf8-fleet.sh'
    Write-Host '===== BEGIN server-fleet-verify =====' -ForegroundColor Cyan
    Write-Report '===== BEGIN server-fleet-verify ====='
    if (-not (Test-Path -LiteralPath $verifySh)) {
        Write-Host 'FAIL  server-fleet (missing publish\_verify-utf8-fleet.sh)' -ForegroundColor Red
        Write-Report 'FAIL missing verify script'
        $fail++
    } else {
        try {
            $scpOut = & scp.exe -o BatchMode=yes -o ConnectTimeout=15 $verifySh ("{0}:/tmp/verify-utf8-fleet.sh" -f $ServerHost) 2>&1 | Out-String
            Write-Report $scpOut
            $stdout = ''
            $stderr = ''
            $timedOut = $false
            $ec = [ClaudeConnect.TestProcRunnerV4]::Run(
                'ssh.exe',
                ('-o BatchMode=yes -o ConnectTimeout=60 {0} sudo-from-laptop --smart -- bash /tmp/verify-utf8-fleet.sh' -f $ServerHost),
                $RepoRoot,
                120000,
                [ref]$stdout, [ref]$stderr, [ref]$timedOut
            )
            $srv = $stdout
            if ($stderr) { $srv = $srv + "`n" + $stderr }
            Write-Report $srv
            Write-Report ('EXIT={0}' -f $ec)
            if ($timedOut) {
                Write-Host 'TIMEOUT server-fleet' -ForegroundColor Red
                $fail++
            } elseif ($srv -match 'ALL_SERVER_ASSERTS_PASSED' -and $ec -eq 0) {
                Write-Host 'PASS  server-fleet' -ForegroundColor Green
            } else {
                Write-Host ('FAIL  server-fleet EXIT={0}' -f $ec) -ForegroundColor Red
                $fail++
            }
        } catch {
            Write-Host ("FAIL  server-fleet ({0})" -f $_.Exception.Message) -ForegroundColor Red
            Write-Report ("FAIL server-fleet exception: {0}" -f $_.Exception.Message)
            $fail++
        }
    }
}

Write-Host ''
Write-Report ('===== SUMMARY fail={0} =====' -f $fail)
if ($fail -eq 0) {
    Write-Host 'HARD UTF-8 / MCP FLEET: ALL PASS' -ForegroundColor Green
    Write-Host ("LOG {0}" -f $ReportPath) -ForegroundColor DarkGray
    exit 0
}
Write-Host ("HARD UTF-8 / MCP FLEET: {0} FAILED" -f $fail) -ForegroundColor Red
Write-Host ("LOG {0}" -f $ReportPath) -ForegroundColor DarkGray
exit 1
