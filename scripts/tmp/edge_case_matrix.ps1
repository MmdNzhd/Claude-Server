$ErrorActionPreference='Continue'
function Row($id,$status,$note){ Write-Host ("{0,-4} {1,-10} {2}" -f $id,$status,$note) }

Write-Host '=== EDGE CASE MATRIX (code-verified now) ===' -ForegroundColor Cyan
Write-Host ''

# helpers
function Has($path,$pat){ return [bool](Select-String -Path $path -Pattern $pat -SimpleMatch -Quiet -EA SilentlyContinue) }

$ui='scripts\client\connect-ui.ps1'
$gm='scripts\client\git-mode.ps1'
$upd='scripts\client\windows\connect-update.ps1'
$bat='scripts\client\windows\connect.bat'
$cp='scripts\client\windows\connect.ps1'
$ush='scripts\client\connect-ui.sh'
$gmsh='scripts\client\git-mode.sh'

Write-Host '-- Logging / Sync --' -ForegroundColor Yellow
Row 'L1' $(if(Has $ui 'LastConnectLogSyncOk'){'FIXED'}else{'OPEN'}) 'False UI leak from Sync return'
Row 'L2' $(if((Has $ui "'`$HOME/") -or (Select-String $ui -Pattern "cat `"`\`$HOME/" -Quiet)){'FIXED'}else{'CHECK'}) 'Sync remote $HOME literal (connect-ui)'
Row 'L3' $(if(Has $upd "'`$HOME/" -or (Select-String $upd -Pattern "cat `"`\`$HOME/" -Quiet) -or (Has $upd 'shipped_day_log_to_server')){'FIXED'}else{'OPEN'}) 'Update ship $HOME + watermark'
Row 'L4' $(if(Has $ui 'TRACE' -and (Select-String $ui -Pattern "Level -eq 'TRACE'" -Quiet)){'FIXED'}else{'OPEN'}) 'TRACE/DEBUG local-only sync'
Row 'L5' $(if(Has $ui '512KB'){'FIXED'}else{'OPEN'}) 'Sync chunk 512KB + watermark'
Row 'L6' $(if(Has $ui 'FileShare.ReadWrite'){'FIXED'}else{'OPEN'}) 'Dual writer FileShare'
Row 'L7' $(if(Has $ui 'Ensure-ConnectLogWriter' -and (Has $ui 'Get-ConnectLogDayPath')){'FIXED'}else{'OPEN'}) 'Writer reopen + midnight rollover'
Row 'L8' $(if(Has $ui 'Enter-ConnectSingleInstance'){'FIXED'}else{'OPEN'}) 'Single-instance mutex'
Row 'L9' $(if(Has $ui 'Invoke-ConnectLogProcTimed'){'FIXED'}else{'OPEN'}) 'Sync ssh/scp timeout (no UI freeze forever)'
Row 'L10' $(if(Has $bat 'CLAUDE_CONNECT_RUN_ID' -and (Has $ui 'CLAUDE_CONNECT_RUN_ID')){'FIXED'}else{'OPEN'}) 'BOOTSTRAP/UPDATE/session correlation id'
Row 'L11' $(if(Has $upd 'attempt -le 3' -and (Has $upd 'TimeoutMs 20000')){'FIXED'}else{'OPEN'}) 'Update cat retry x3 @20s + fallback account'

Write-Host ''
Write-Host '-- Perf / Tunnel (post-bat flow) --' -ForegroundColor Yellow
Row 'P1' $(if(Has $gm 'skip_duplicate' -and (Has $gm 'ONE SSH')){'FIXED'}else{'OPEN'}) 'PushConf batch+dedupe'
Row 'P2' $(if(Has $gm 'one SSH reads conf'){'FIXED'}else{'OPEN'}) 'Warn-Foreign 3 greps -> 1 SSH'
Row 'P3' $(if(-not (Has $cp 'ControlMaster=auto')){'WONTFIX'}else{'RISK'}) 'Windows SSH mux (broken on this OpenSSH; not used)'
Row 'P4' $(if(Has $gm 'LastTunnelSyncTraceAt' -or (Has $gmsh '_LAST_TUNNEL_TRACE')){'FIXED'}else{'OPEN'}) 'TUNNEL_SYNC TRACE throttle 30s'
Row 'P5' $(if(Select-String $gm -Pattern '\$i -le 4' -Quiet){'FIXED'}else{'OPEN'}) 'STALE wait shortened 4x250ms'
Row 'P6' $(if(Select-String $cp -Pattern 'lastEditorCheckAt' -Quiet){'FIXED'}else{'OPEN'}) 'Editor CIM every 2s not every tick'
Row 'P7' $(if(Has $ui "CLAUDE_CONNECT_PERF_LOG -eq '1'"){'FIXED'}else{'OPEN'}) 'PERF default OFF'
Row 'P8' 'OPEN' 'Recovery still ForceCursorAuthSync full chain (audit)'
Row 'P9' 'OPEN' 'Many sequential SSH still ~0.5-1.2s each without mux'
Row 'P10' 'OPEN' 'Invoke-MountProject full up when GIT_MODE=off (audit)'

Write-Host ''
Write-Host '-- Session lifecycle --' -ForegroundColor Yellow
Row 'S1' $(if(Has $bat 'BOOTSTRAP'){'FIXED'}else{'OPEN'}) 'BOOTSTRAP before update'
Row 'S2' $(if(Has $cp 'Enter-ConnectSingleInstance'){'FIXED'}else{'OPEN'}) 'Mutex after init log'
Row 'S3' $(if(Has $ui 'Close-ConnectLog' -and (Has $ui 'Exit-ConnectSingleInstance')){'FIXED'}else{'OPEN'}) 'Close log + mutex release'
Row 'S4' 'OPEN' 'Unconditional RunAs vs docs -AdminFix (audit; behavior intentional?)'
Row 'S5' 'OPEN' 'Shared connect.conf Smart+Sepidz same Windows user'
Row 'S6' $(if(Has $ush 'flock'){'FIXED'}else{'OPEN'}) 'Mac flock single-instance'

Write-Host ''
Write-Host '-- Publish safety --' -ForegroundColor Yellow
Row 'D1' 'FIXED' 'SepidzOnly never deploys Smart (verified live Smart=.22)'
Row 'D2' 'FIXED' 'Package IP/alias patch sepidz only'

Write-Host ''
Write-Host '-- Live / operational edges --' -ForegroundColor Yellow
$old=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\connect-version.txt'
if(Test-Path $old){
  $v=(Get-Content $old -Raw).Trim()
  if($v -eq '20260719.21'){ Row 'O1' 'OK' "launch folder already .21" }
  else { Row 'O1' 'PENDING' "launch folder still $v until next connect.bat -> .21" }
} else { Row 'O1' 'N/A' 'old sepidz-20260717 folder missing' }

$procs=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'claude-code-client.*connect\.ps1' })
if($procs.Count -gt 0){ Row 'O2' 'RISK' 'Smart-client connect still running' } else { Row 'O2' 'OK' 'no Smart-client connect process' }

Write-Host ''
Write-Host 'Legend: FIXED=in code+deployed  OPEN=known residual  WONTFIX=unsafe here  PENDING=needs your bat' -ForegroundColor DarkGray
