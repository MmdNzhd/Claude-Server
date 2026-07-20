$ErrorActionPreference='Continue'
$fail=0
function Ok($m){Write-Host "[OK] $m"}
function Bad($m){Write-Host "[FAIL] $m"; $script:fail++}
function Info($m){Write-Host "[..] $m"}

. .\scripts\client\connect-ui.ps1

# batch 25 exact line
$line = (Select-String -Path scripts\client\connect-ui.ps1 -Pattern 'ConnectLogLinesSinceSync').Line
Info "batch lines: $($line -join ' | ')"
if ($line -match '-ge 25') { Ok 'INFO batch every 25' } else { Bad 'batch 25 missing' }

$verS = (ssh -o BatchMode=yes -o ConnectTimeout=12 smart@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
$verM = (ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
if ($verS -eq '20260719.11') { Ok "Sepidz=$verS" } else { Bad "Sepidz=$verS" }
if ($verM -eq '20260717.22') { Ok "Smart frozen=$verM" } else { Bad "Smart=$verM" }

# remote bundle fixes
$chk = ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 'grep -c LastConnectLogSyncOk /usr/local/share/claude-client/connect-ui.ps1; grep -c "ConnectLogLinesSinceSync -ge 25" /usr/local/share/claude-client/connect-ui.ps1; grep -c "return \$false" /usr/local/share/claude-client/connect-ui.ps1; grep -c "same folder as connect.bat" /usr/local/share/claude-client/connect.ps1; grep -c "function Sync-ConnectLogToServer" /usr/local/share/claude-client/connect-ui.ps1'
Info "remote counts (LastConnectOk, ge25, return_false, samefolder, syncfuncs): $chk"
$parts = @($chk -split '\s+')
if ([int]$parts[0] -ge 1) { Ok 'remote has LastConnectLogSyncOk' } else { Bad 'remote missing LastConnectLogSyncOk' }
if ([int]$parts[1] -ge 1) { Ok 'remote has batch 25' } else { Bad 'remote missing batch 25' }
if ([int]$parts[2] -eq 0) { Ok 'remote Sync has no return $false' } else { Info "return `$false count=$($parts[2]) (may be elsewhere)" }
if ([int]$parts[3] -eq 0) { Ok 'remote connect.ps1 no wrong log path msg' } else { Bad 'remote still has same folder as connect.bat' }
if ([int]$parts[4] -eq 1) { Ok 'remote single Sync function' } else { Bad "remote Sync count=$($parts[4])" }

# local log completeness
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$lines = Get-Content $local
Ok ("local bytes=$((Get-Item $local).Length) lines=$($lines.Count)")
foreach ($pat in @('BOOTSTRAP: connect.bat start','session start v20260719','DECISION: project_select','SESSION_LOOP begin','LAUNCH begin')) {
  if ($lines | Select-String -SimpleMatch $pat | Select-Object -First 1) { Ok "local has $pat" } else { Bad "local missing $pat" }
}

# server log completeness  
$srv = ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 'wc -c $HOME/.claude/logs/connect-20260719.log; grep -c BOOTSTRAP $HOME/.claude/logs/connect-20260719.log; grep -c "session start" $HOME/.claude/logs/connect-20260719.log; grep -c "DECISION: project_select" $HOME/.claude/logs/connect-20260719.log; head -n1 $HOME/.claude/logs/connect-20260719.log'
Info "server: $srv"
$sp = @($srv -split "`n")
if ([int64]$sp[0].Trim().Split()[0] -gt 100000) { Ok "server log size ok: $($sp[0])" } else { Bad "server log too small: $($sp[0])" }
if ([int]$sp[1] -ge 1) { Ok 'server has BOOTSTRAP' } else { Bad 'server missing BOOTSTRAP' }
if ([int]$sp[2] -ge 1) { Ok 'server has session start' } else { Bad 'server missing session start' }
if ([int]$sp[3] -ge 1) { Ok 'server has DECISION' } else { Bad 'server missing DECISION' }

# live sync probe
$probe = "VERIFY_PROBE2_$(Get-Date -Format 'yyyyMMddHHmmss')_$PID"
Add-Content -LiteralPath $local -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [INFO] [verify] $probe" -Encoding utf8
$script:Alias = 'smart@192.168.250.70'
$script:ConnectLogPath = $local
$script:ConnectLogWriter = $null
$script:ConnectSessionId = 'verify2'
$wmPath = $local + '.sync-offset'
if (Test-Path $wmPath) { $script:ConnectLogSyncOffset = [int]((Get-Content $wmPath -Raw).Trim()) }
else { $script:ConnectLogSyncOffset = [Math]::Max(0, (Get-Item $local).Length - 4096) }
Info "sync from offset=$($script:ConnectLogSyncOffset) size=$((Get-Item $local).Length)"

$pipeOut = Sync-ConnectLogToServer | Out-String
if ([string]::IsNullOrWhiteSpace($pipeOut)) { Ok 'Sync pipeline empty (no False)' } else { Bad "pipeline leak: [$pipeOut]" }
Info "LastConnectLogSyncOk=$script:LastConnectLogSyncOk"
if (-not $script:LastConnectLogSyncOk) { Bad 'LastConnectLogSyncOk was false' } else { Ok 'LastConnectLogSyncOk true' }

$found = ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 "grep -F `"$probe`" `$HOME/.claude/logs/connect-20260719.log | tail -1"
if ($found -match 'VERIFY_PROBE2') { Ok "live sync on server OK" } else { Bad "probe not on server: $found" }

Write-Host ''
if ($fail -eq 0) { Write-Host '==== ALL CHECKS PASSED ====' } else { Write-Host "==== FAILED=$fail ===="; exit 1 }
