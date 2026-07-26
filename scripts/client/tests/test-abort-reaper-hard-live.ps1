# test-abort-reaper-hard-live.ps1
# Hard live suite: server abort/reaper gates + Windows heartbeat stop + no orphan PS.
# Prerequisite: connect UP (tunnel to Smart).
#   powershell -NoProfile -File scripts\client\tests\test-abort-reaper-hard-live.ps1
$ErrorActionPreference = 'Stop'
$Server = if ($env:CLAUDE_HARD_SERVER) { $env:CLAUDE_HARD_SERVER } else { 'smart@192.168.210.240' }
$Repo = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
if (-not (Test-Path (Join-Path $Repo 'scripts\server\tests\test-abort-reaper-hard.sh'))) {
    $Repo = 'D:\Smart\Claude-Code-Server'
}
$ServerTest = Join-Path $Repo 'scripts\server\tests\test-abort-reaper-hard.sh'
$Pass = 0; $Fail = 0
function Ok([string]$m) { Write-Host "  PASS $m"; $script:Pass++ }
function Bad([string]$m) { Write-Host "  FAIL $m"; $script:Fail++ }

Write-Host ''
Write-Host '=== HARD LIVE: abort + reaper ==='
Write-Host "server=$Server repo=$Repo"
Write-Host ''

# Upload + run server hard script
scp -o BatchMode=yes -o ConnectTimeout=15 $ServerTest "${Server}:/tmp/test-abort-reaper-hard.sh" | Out-Null
$serverOut = ssh -o BatchMode=yes -o ConnectTimeout=120 $Server 'HARD_ABORT_N=4 bash /tmp/test-abort-reaper-hard.sh 2>&1'
Write-Host $serverOut
if ($LASTEXITCODE -eq 0 -and $serverOut -match 'SERVER HARD: .* 0 failed') { Ok 'server hard suite (H1-H3,H6-H8)' }
elseif ($serverOut -match '0 failed') { Ok 'server hard suite' }
else { Bad 'server hard suite failed' }

# H4 heartbeat growth gate (laptop-observed)
$hb = Join-Path $Repo '.tmp-hard-hb.txt'
$ps1 = Join-Path $Repo '.tmp-hard-hb.ps1'
Remove-Item $hb -Force -EA SilentlyContinue
@'
$p = Join-Path (Split-Path $PSCommandPath -Parent) '..\..\.tmp-hard-hb.txt'
# rewritten below with absolute path
'@ | Out-Null
@"
`$p = '$($hb -replace "'","''")'
'START' | Set-Content -LiteralPath `$p
1..90 | ForEach-Object { Start-Sleep -Seconds 1; Add-Content -LiteralPath `$p -Value ('tick ' + `$_ + ' ' + (Get-Date -Format o)) }
"@ | Set-Content -LiteralPath $ps1 -Encoding utf8

$startHb = @'
set +e
pkill -f 'tmp-hard-hb' 2>/dev/null || true
sleep 1
nohup laptop-exec run -p refactoreoldclub -- powershell -NoProfile -File 'REPO_PS1' >/tmp/hard-hb.out 2>&1 &
sleep 4
LE=$(pgrep -n -f 'laptop-exec run -p refactoreoldclub -- powershell')
echo "$LE" >/tmp/hard-hb.le
TO=$(ps -o pid= --ppid "$LE" | awk '{print $1; exit}')
SSH=$(ps -o pid= --ppid "$TO" | awk '{print $1; exit}')
echo "$TO" >/tmp/hard-hb.to
echo "$SSH" >/tmp/hard-hb.ssh
echo "HB_TREE LE=$LE TO=$TO SSH=$SSH"
'@ -replace 'REPO_PS1', ($ps1 -replace '\\', '/')
# Windows path for -File must stay backslash
$startHb = @"
set +e
pkill -f 'tmp-hard-hb' 2>/dev/null || true
sleep 1
nohup laptop-exec run -p refactoreoldclub -- powershell -NoProfile -File '$ps1' >/tmp/hard-hb.out 2>&1 &
sleep 4
LE=`$(pgrep -n -f 'laptop-exec run -p refactoreoldclub -- powershell')
echo "`$LE" >/tmp/hard-hb.le
TO=`$(ps -o pid= --ppid "`$LE" | awk '{print `$1; exit}')
SSH=`$(ps -o pid= --ppid "`$TO" | awk '{print `$1; exit}')
echo "`$TO" >/tmp/hard-hb.to
echo "`$SSH" >/tmp/hard-hb.ssh
echo "HB_TREE LE=`$LE TO=`$TO SSH=`$SSH"
head -n 3 /tmp/hard-hb.out
"@
$tmp = Join-Path $env:TEMP 'hard-hb-start.sh'
[IO.File]::WriteAllText($tmp, ($startHb -replace "`r", ''))
scp -o BatchMode=yes $tmp "${Server}:/tmp/hard-hb-start.sh" | Out-Null
Write-Host (ssh -o BatchMode=yes $Server 'bash /tmp/hard-hb-start.sh')

$ready = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep 1
    if ((Test-Path $hb) -and (@(Get-Content $hb | Where-Object { $_ -match '^tick' }).Count -ge 3)) { $ready = $true; break }
}
if (-not $ready) {
    Bad 'H4 heartbeat did not start'
    ssh -o BatchMode=yes $Server 'cat /tmp/hard-hb.out 2>/dev/null | tail -n 20'
} else {
    $before = @(Get-Content $hb | Where-Object { $_ -match '^tick' }).Count
    ssh -o BatchMode=yes $Server 'kill -TERM $(cat /tmp/hard-hb.le); sleep 6; for p in $(cat /tmp/hard-hb.le) $(cat /tmp/hard-hb.to) $(cat /tmp/hard-hb.ssh); do kill -0 $p 2>/dev/null && echo ALIVE $p || echo DEAD $p; done'
    Start-Sleep 5
    $mid = @(Get-Content $hb -EA SilentlyContinue | Where-Object { $_ -match '^tick' }).Count
    Start-Sleep 5
    $end = @(Get-Content $hb -EA SilentlyContinue | Where-Object { $_ -match '^tick' }).Count
    Write-Host "  H4 ticks before=$before mid=$mid end=$end"
    if ($end -eq $mid) { Ok "H4 heartbeat stopped growing (end=$end)" }
    else { Bad "H4 still growing mid=$mid end=$end" }
}

# H5: no young empty-cmdline powershell under sshd->cmd
Start-Sleep 2
$all = @(Get-CimInstance Win32_Process -EA SilentlyContinue)
$sshd = @($all | Where-Object { $_.Name -eq 'sshd.exe' } | ForEach-Object { $_.ProcessId })
$badPs = New-Object System.Collections.Generic.List[object]
foreach ($p in $all) {
    if ($p.Name -notmatch 'powershell|pwsh') { continue }
    if ($p.CommandLine -and $p.CommandLine.Length -gt 0) { continue }
    if (-not $p.CreationDate) { continue }
    if (((Get-Date) - $p.CreationDate).TotalSeconds -gt 30) { continue }
    $parent = $all | Where-Object { $_.ProcessId -eq $p.ParentProcessId } | Select-Object -First 1
    if ($parent -and $parent.Name -eq 'cmd.exe' -and $sshd -contains $parent.ParentProcessId) {
        $badPs.Add($p) | Out-Null
    }
}
if ($badPs.Count -eq 0) { Ok 'H5 no young empty-cmdline powershell under sshd/cmd' }
else { Bad ("H5 orphan powershell pids={0}" -f (($badPs | ForEach-Object { $_.ProcessId }) -join ',')) }

# cleanup
ssh -o BatchMode=yes $Server 'pkill -f tmp-hard-hb 2>/dev/null; pkill -f HARDABORT_SLEEP 2>/dev/null; pkill -f "laptop-exec run -p refactoreoldclub -- powershell" 2>/dev/null; true' | Out-Null
Remove-Item $hb, $ps1 -Force -EA SilentlyContinue

Write-Host ''
Write-Host ("=== HARD LIVE RESULT: {0} passed, {1} failed ===" -f $Pass, $Fail)
if ($Fail -gt 0) { exit 1 } else { exit 0 }
