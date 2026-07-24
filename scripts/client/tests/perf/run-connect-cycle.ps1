param(
    [Parameter(Mandatory)][int]$ProjectSlot,
    [string]$ConnectBootPath = 'C:\Users\Smart\Desktop\Claude-Connect\connect-boot.ps1',
    [int]$QuietSeconds = 20,
    [int]$MaxSeconds = 180,
    [string]$ResultsDir = (Join-Path $env:USERPROFILE '.config\claude-connect\perf-harness')
)
# NOTE (known limitation, discovered while validating #P7): the PROJECT-SELECTION menu
# inside connect.ps1/connect-ui.ps1 sometimes never receives the -ProjectSlot value written
# to StandardInput here, even though a minimal Read-Host repro with the identical Process.Start
# + redirected-stdin pattern works fine. Root cause was not conclusively pinned down in the
# time available (ruled out: raw [Console]::ReadKey buffer-clearing before the menu - none
# exists on that path; ruled out: connect-boot.ps1 relaunching connect.ps1 as a separate OS
# process - it uses & (dot-invoke) in the same process). Treat SawScorecardBoot/completed runs
# as a bonus, not a guarantee - this harness is still reliable for timing everything UP TO the
# project menu (Laptop SSH key / Server setup / tunnel-up), which is what #P1/#P2/#P3/#P7 were
# actually diagnosed and validated against.
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $ResultsDir -ErrorAction SilentlyContinue | Out-Null

function Get-CursorRootPids {
    $cp = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue)
    $allPids = @($cp | ForEach-Object { $_.ProcessId })
    @($cp | Where-Object { $allPids -notcontains $_.ParentProcessId } | ForEach-Object { $_.ProcessId })
}
function Get-MainTunnelPids {
    @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '-N ' -and $_.CommandLine -match '-R ' } |
        ForEach-Object { $_.ProcessId })
}
function Stop-ProcessTree {
    param([int]$RootPid)
    $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$RootPid" -ErrorAction SilentlyContinue)
    foreach ($k in $kids) { Stop-ProcessTree -RootPid $k.ProcessId }
    try { Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue } catch {}
}

$protectedCursor = @(Get-CursorRootPids)
$protectedTunnel = @(Get-MainTunnelPids)
Write-Output ("PROTECT cursor=[{0}] tunnel=[{1}]" -f ($protectedCursor -join ','), ($protectedTunnel -join ','))

$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$todayLog = Join-Path $logDir ("connect-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

$startTime = Get-Date
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $ConnectBootPath + '"'
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$stdoutSb = New-Object System.Text.StringBuilder
$evAction = { if ($EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) } }
$outSub = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $evAction -MessageData $stdoutSb
$errSub = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $evAction -MessageData $stdoutSb
$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()

Start-Sleep -Milliseconds 900
try { $proc.StandardInput.WriteLine([string]$ProjectSlot) } catch {}

$sid = $null
$steps = @()
$sawScorecardBoot = $false
$lastActivity = Get-Date
$lastLineCount = 0

while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
    Start-Sleep -Milliseconds 1500
    if ($proc.HasExited) { break }

    $lines = @()
    if (Test-Path -LiteralPath $todayLog) {
        try { $lines = Get-Content -LiteralPath $todayLog -ErrorAction SilentlyContinue -Tail 400 } catch { $lines = @() }
    }
    if (-not $sid) {
        foreach ($line in $lines) {
            if ($line -match ("pid=" + $proc.Id + "\s+session=(\S+)")) { $sid = $Matches[1]; break }
        }
    }
    if ($sid) {
        $tag = "[$sid]"
        $tagged = @($lines | Where-Object { $_.Contains($tag) })
        if ($tagged.Count -ne $lastLineCount) {
            $lastActivity = Get-Date
            $lastLineCount = $tagged.Count
        }
        $steps = @()
        foreach ($line in $tagged) {
            if ($line -match 'STEP end: (.+?) (ok|failed) ms=(\d+)') {
                $steps += [PSCustomObject]@{ Name = $Matches[1]; Status = $Matches[2]; Ms = [int]$Matches[3] }
            }
            if ($line -match 'SCORECARD boot ') { $sawScorecardBoot = $true }
        }
        if ($sawScorecardBoot) { break }
    }
    if (((Get-Date) - $lastActivity).TotalSeconds -ge $QuietSeconds -and $sw.Elapsed.TotalSeconds -gt 15) { break }
}
$sw.Stop()
$totalMs = [int]$sw.ElapsedMilliseconds
$exitedNaturally = $proc.HasExited

if (-not $exitedNaturally) { Stop-ProcessTree -RootPid $proc.Id }
Start-Sleep -Seconds 2

$afterCursor = @(Get-CursorRootPids)
$newCursor = @($afterCursor | Where-Object { $protectedCursor -notcontains $_ })
foreach ($ncp in $newCursor) { try { Stop-Process -Id $ncp -Force -ErrorAction SilentlyContinue } catch {} }

$afterTunnel = @(Get-MainTunnelPids)
$newTunnel = @($afterTunnel | Where-Object { $protectedTunnel -notcontains $_ })
foreach ($nt in $newTunnel) { try { Stop-Process -Id $nt -Force -ErrorAction SilentlyContinue } catch {} }

try { Unregister-Event -SourceIdentifier $outSub.Name -ErrorAction SilentlyContinue } catch {}
try { Unregister-Event -SourceIdentifier $errSub.Name -ErrorAction SilentlyContinue } catch {}

$scorecardLine = $null
if ($sid -and (Test-Path -LiteralPath $todayLog)) {
    $tag = "[$sid]"
    $scLines = Get-Content -LiteralPath $todayLog -ErrorAction SilentlyContinue | Where-Object { $_.Contains($tag) -and $_ -match 'SCORECARD boot' }
    if ($scLines) { $scorecardLine = ($scLines | Select-Object -Last 1) }
}

$result = [PSCustomObject]@{
    ProjectSlot         = $ProjectSlot
    StartTime           = $startTime.ToString('o')
    TotalMs             = $totalMs
    ProcPid             = $proc.Id
    ProcExitedNaturally = $exitedNaturally
    SawScorecardBoot    = $sawScorecardBoot
    SessionId           = $sid
    Steps               = $steps
    ScorecardLine       = $scorecardLine
    NewCursorClosed     = $newCursor
    NewTunnelClosed     = $newTunnel
    StdoutTail          = (($stdoutSb.ToString() -split "`r?`n") | Select-Object -Last 60) -join "`n"
}
$resultFile = Join-Path $ResultsDir ("cycle-{0}-{1}.json" -f $ProjectSlot, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultFile -Encoding UTF8
Write-Output "RESULT_FILE=$resultFile"
Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
