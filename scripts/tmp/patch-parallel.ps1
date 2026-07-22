$ErrorActionPreference = 'Stop'
$gm = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$old = @'
    $script = @"
for p in $list; do
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/`$p" 2>/dev/null; then echo OPEN:`$p; fi
done
"@
'@
# find Get-ServerOpenTunnelPorts body and replace the loop
$i = $g.IndexOf('function Get-ServerOpenTunnelPorts')
$j = $g.IndexOf('function Acquire-TunnelPort')
if ($i -lt 0 -or $j -lt 0) { throw 'bounds' }
$fn = $g.Substring($i, $j - $i)
if ($fn -match 'wait\b') { Write-Host 'already parallel?' }

$newFn = @'
function Get-ServerOpenTunnelPorts {
    param([Parameter(Mandatory)][int[]]$Ports)
    $set = New-Object "System.Collections.Generic.HashSet[int]"
    if (-not $Ports -or $Ports.Count -eq 0) { return $set }
    $list = ($Ports | Select-Object -Unique) -join ' '
    # One SSH, parallel short probes — closed ports fail in ~250ms, not 1s serial each.
    $script = @"
for p in $list; do
  ( timeout 0.25 bash -c "exec 3<>/dev/tcp/127.0.0.1/`$p" 2>/dev/null && echo OPEN:`$p ) &
done
wait
"@
    $out = (SshX $script 2>$null) -join "`n"
    foreach ($line in @($out -split "`n")) {
        if ($line -match 'OPEN:(\d+)') { [void]$set.Add([int]$Matches[1]) }
    }
    Write-GitModeLog ("ACQUIRE_BATCH open_ports={0} probed={1}" -f (($set | Sort-Object) -join ','), $Ports.Count) 'DEBUG'
    return $set
}

'@
$nl = if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }
if ($nl -eq "`r`n") { $newFn = $newFn -replace "(?<!\r)`n", "`r`n" }
$g = $g.Remove($i, $j - $i).Insert($i, $newFn)
[IO.File]::WriteAllText($gm, $g)
$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm,[ref]$null,[ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse' }
Write-Host 'OK parallel probe'

# republish without version bump - still .13
$root = 'D:\Smart\Claude-Code-Server'
& (Join-Path $root 'publish\publish.ps1') -SmartOnly -SkipVersionBump | Out-Host
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'
foreach ($t in @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows')
)) {
  Copy-Item (Join-Path $pub 'git-mode.ps1') (Join-Path $t 'git-mode.ps1') -Force
  Write-Host ("SYNC_GM {0} parallel={1}" -f $t, [int]((Get-Content (Join-Path $t 'git-mode.ps1') -Raw) -match 'timeout 0\.25'))
}
