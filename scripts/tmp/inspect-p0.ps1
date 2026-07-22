$ErrorActionPreference='Continue'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
Write-Host "ROOT=$(Get-Location)"

Write-Host "`n== Begin-ConnectRecovery / Silent ==" -ForegroundColor Cyan
Select-String -Path scripts/client/windows/connect.ps1 -Pattern 'function Begin-ConnectRecovery|Invoke-ConnectSilentUpdateCheck|function Complete-PostTunnelRecovery|UPDATE_SILENT' |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Host "`n== Write-TunnelDropLog head ==" -ForegroundColor Cyan
Get-Content scripts/client/git-mode.ps1 | Select-Object -Skip 36 -First 15 | ForEach-Object -Begin {$i=37} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }

Write-Host "`n== Remove-LocalOrphanTunnel ==" -ForegroundColor Cyan
$lines = Get-Content scripts/client/git-mode.ps1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Remove-LocalOrphanTunnel') {
    for ($j=$i; $j -lt [Math]::Min($i+35,$lines.Count); $j++) { Write-Host ("{0}|{1}" -f ($j+1), $lines[$j]) }
    break
  }
}

Write-Host "`n== Launch exhaust ==" -ForegroundColor Cyan
Get-Content scripts/client/editor-launch.ps1 | Select-Object -Skip 1455 -First 20 | ForEach-Object -Begin {$i=1456} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }

Write-Host "`n== Silent update tunnel gate ==" -ForegroundColor Cyan
Select-String -Path scripts/client/connect-ui.ps1 -Pattern 'tunnel_down|Test-TunnelUp|last-update-check|pending_restart|UPDATE_SILENT' |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Host "`n== Enter-ConnectSingleInstance ==" -ForegroundColor Cyan
$lines = Get-Content scripts/client/connect-ui.ps1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Enter-ConnectSingleInstance') {
    for ($j=$i; $j -lt [Math]::Min($i+40,$lines.Count); $j++) { Write-Host ("{0}|{1}" -f ($j+1), $lines[$j]) }
    break
  }
}

Write-Host "`n== git-hide loops ==" -ForegroundColor Cyan
Select-String -Path scripts/server/claude-mount.sh -Pattern 'while|Sleep|sleep|n -lt|GIT_HIDE' |
  Select-Object -First 25 |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length))) }

Write-Host "`n== hard-multi section A ==" -ForegroundColor Cyan
Get-Content scripts/client/tests/test-hard-multi-agent-regressions.ps1 | Select-Object -Skip 40 -First 25 | ForEach-Object -Begin {$i=41} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }

Write-Host "`n== -Pid TunnelDrop call sites ==" -ForegroundColor Cyan
Select-String -Path scripts/client/*.ps1,scripts/client/windows/*.ps1 -Pattern 'Write-TunnelDropLog|TunnelPid|-Pid \$' |
  ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Path.Replace((Get-Location).Path+'\',''), $_.LineNumber, $_.Line.Trim()) }
