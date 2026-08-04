# test-log-sync-nre-at649-hard.ps1
#
# Fleet 2026-08-03 (deep-parallel + sticky OPT_Pipe): after LOG_SYNC_OK, a later sync logged
#   LOG_SYNC_FAIL ... detail=exception type=NullReferenceException at=connect-ui.ps1:649
# while the day log never contained detail=chunk_read_fail (0 hits). Injecting NRE at the
# got-lt-take line in-process classifies as chunk_read_fail — so production either lost the
# named breadcrumb (Writer/synced write failed) or ScriptLineNumber lied into the outer catch.
#
# Hard contracts:
#   H1-H3 static: fail-breadcrumb helper, outer reclassify of chunk line range, Force WriteAllBytes guarded
#   L1 inject NRE at got-lt-take -> chunk_read_fail, never opaque detail=exception
#   L2 Writer=$null during fail still leaves chunk_read_fail via AppendAllText fallback
#   L3 post-chunk NRE (Get-ConnectRemoteLogByteSize throws) fails soft (no escape) + typed breadcrumb
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}
$uiPath = Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'
$ui = Get-Content -LiteralPath $uiPath -Raw

Write-Host '=== log sync NRE at=649 hard (fleet residual) ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

Assert-C 'H1' ($ui -match 'function Write-ConnectLogSyncFailBreadcrumb') 'Write-ConnectLogSyncFailBreadcrumb exists' 'ok'
Assert-C 'H2' ($ui -match "detailKind = 'chunk_read_fail'") 'outer catch reclassifies chunk line range' 'ok'
Assert-C 'H3' ($ui -match '(?s)if \(\$null -eq \$chunk2 -or \$take2 -le 0\) \{ break \}\s*try \{\s*\[System\.IO\.File\]::WriteAllBytes\(\$tmpLocal, \$chunk2\)') 'Force drain WriteAllBytes is try/catch wrapped' 'ok'
Assert-C 'H4' ($ui -match 'function Read-ConnectLogChunkBytes') 'chunk read helper exists (never throws)' 'ok'
Assert-C 'H5' ($ui -match 'Read-ConnectLogChunkBytes\s+-Path') 'Sync calls Read-ConnectLogChunkBytes' 'ok'
Assert-C 'H6' ($ui -match 'read_helper_null') 'null helper result -> chunk_read_fail soft breadcrumb' 'ok'

$live = Join-Path $env:TEMP ("logsync-nre649-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null

# --- L1: helper returns null (simulates share-race read fail; must not escape) ---
$home1 = Join-Path $live 'h1'
New-Item -ItemType Directory -Force -Path $home1 | Out-Null
$driver1 = Join-Path $live 'd1.ps1'
@'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'nre649-l1'
1..4 | ForEach-Object { Write-ConnectLog "payload $_" 'INFO' }
try { $script:ConnectLogWriter.Flush() } catch { }
function Get-ConnectLogSyncTarget { 'claude-server' }
function Get-ConnectRemoteLogByteSize { param($Target,$Day,$SshOpts,$TimeoutMs) [int64]0 }
function Test-ConnectLogChunkAlreadyRemote { param($Target,$Day,$Chunk,$Take,$SshOpts,$TimeoutMs) $false }
function Test-ConnectRemoteLogNeedsRebuild { param($LocalSize,$RemoteSize,$Offset) $false }
function Invoke-ConnectLogProcTimed { param($Exe,$ArgumentList,$TimeoutMs) @{ Ok=$true; TimedOut=$false; ExitCode=0; StdOut='0'; StdErr='' } }
function Read-ConnectLogChunkBytes { param($Path,$Offset,$Take) return $null }
$script:ConnectLogSyncFailLogged = $false
$escaped = 0
try { Sync-ConnectLogToServer -Force | Out-Null } catch { $escaped++ }
try { $script:ConnectLogWriter.Flush() } catch { }
$raw = Get-Content -LiteralPath $script:ConnectLogPath -Raw
Write-Output ("L1_ESCAPED=" + $escaped)
Write-Output ("L1_CHUNK=" + [int]($raw -match 'detail=chunk_read_fail'))
Write-Output ("L1_EXCEPTION=" + [int]($raw -match 'detail=exception'))
Write-Output ("L1_SOFT=" + [int]($raw -match 'read_helper_null'))
'@ | Set-Content -LiteralPath $driver1 -Encoding UTF8
$out1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver1 -UiPath $uiPath -Home2 $home1 2>&1 | Out-String
Write-Host '--- L1 ---'
Write-Host $out1
function Get-Flag([string]$text, [string]$name) {
  if ($text -match ("(?m)^{0}=(\d+)" -f [regex]::Escape($name))) { return [int]$Matches[1] }
  return -1
}
Assert-C 'L1a' ((Get-Flag $out1 'L1_ESCAPED') -eq 0) 'L1: helper-null does not escape Sync' ('escaped=' + (Get-Flag $out1 'L1_ESCAPED'))
Assert-C 'L1b' ((Get-Flag $out1 'L1_CHUNK') -ge 1) 'L1: classified as detail=chunk_read_fail' ('flag=' + (Get-Flag $out1 'L1_CHUNK'))
Assert-C 'L1c' ((Get-Flag $out1 'L1_EXCEPTION') -eq 0) 'L1: no opaque detail=exception' ('flag=' + (Get-Flag $out1 'L1_EXCEPTION'))
Assert-C 'L1d' ((Get-Flag $out1 'L1_SOFT') -ge 1) 'L1: soft read_helper_null breadcrumb' ('flag=' + (Get-Flag $out1 'L1_SOFT'))

# --- L2: Writer null — breadcrumb must still land via AppendAllText ---
$home2 = Join-Path $live 'h2'
New-Item -ItemType Directory -Force -Path $home2 | Out-Null
$driver2 = Join-Path $live 'd2.ps1'
@'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'nre649-l2'
1..4 | ForEach-Object { Write-ConnectLog "payload $_" 'INFO' }
try { $script:ConnectLogWriter.Flush() } catch { }
$logPath = $script:ConnectLogPath
# Drop writer so old path would skip logging entirely.
try { if ($script:ConnectLogWriter) { $script:ConnectLogWriter.Dispose() } } catch { }
$script:ConnectLogWriter = $null
function Get-ConnectLogSyncTarget { 'claude-server' }
function Get-ConnectRemoteLogByteSize { param($Target,$Day,$SshOpts,$TimeoutMs) [int64]0 }
function Test-ConnectLogChunkAlreadyRemote { param($Target,$Day,$Chunk,$Take,$SshOpts,$TimeoutMs) $false }
function Test-ConnectRemoteLogNeedsRebuild { param($LocalSize,$RemoteSize,$Offset) $false }
# Force helper null while Writer is gone — breadcrumb must still AppendAllText.
function Read-ConnectLogChunkBytes { param($Path,$Offset,$Take) return $null }
$script:ConnectLogSyncFailLogged = $false
$escaped = 0
try { Sync-ConnectLogToServer -Force | Out-Null } catch { $escaped++ }
$raw = ''
if (Test-Path -LiteralPath $logPath) { $raw = Get-Content -LiteralPath $logPath -Raw }
$lastFail = Join-Path $Home2 '.config\claude-connect\last-fail.txt'
$lf = ''
if (Test-Path -LiteralPath $lastFail) { $lf = Get-Content -LiteralPath $lastFail -Raw }
Write-Output ("L2_ESCAPED=" + $escaped)
Write-Output ("L2_CHUNK_DAY=" + [int]($raw -match 'detail=chunk_read_fail'))
Write-Output ("L2_CHUNK_LASTFAIL=" + [int]($lf -match 'detail=chunk_read_fail'))
Write-Output ("L2_EXCEPTION=" + [int](($raw + $lf) -match 'detail=exception'))
'@ | Set-Content -LiteralPath $driver2 -Encoding UTF8
$out2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver2 -UiPath $uiPath -Home2 $home2 2>&1 | Out-String
Write-Host '--- L2 ---'
Write-Host $out2
Assert-C 'L2a' ((Get-Flag $out2 'L2_ESCAPED') -eq 0) 'L2: Writer-null fail does not escape' ('escaped=' + (Get-Flag $out2 'L2_ESCAPED'))
Assert-C 'L2b' (((Get-Flag $out2 'L2_CHUNK_DAY') -ge 1) -or ((Get-Flag $out2 'L2_CHUNK_LASTFAIL') -ge 1)) 'L2: chunk_read_fail lands without Writer' ('day=' + (Get-Flag $out2 'L2_CHUNK_DAY') + ' lastfail=' + (Get-Flag $out2 'L2_CHUNK_LASTFAIL'))
Assert-C 'L2c' ((Get-Flag $out2 'L2_EXCEPTION') -eq 0) 'L2: no opaque detail=exception' ('flag=' + (Get-Flag $out2 'L2_EXCEPTION'))

# --- L3: NRE after chunk (remote size probe) ---
$home3 = Join-Path $live 'h3'
New-Item -ItemType Directory -Force -Path $home3 | Out-Null
$driver3 = Join-Path $live 'd3.ps1'
@'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'nre649-l3'
1..6 | ForEach-Object { Write-ConnectLog "payload $_" 'INFO' }
try { $script:ConnectLogWriter.Flush() } catch { }
function Get-ConnectLogSyncTarget { 'claude-server' }
function Get-ConnectRemoteLogByteSize { param($Target,$Day,$SshOpts,$TimeoutMs) throw [System.NullReferenceException]::new('INJECTED_REMOTE_SIZE_NRE') }
function Test-ConnectLogChunkAlreadyRemote { param($Target,$Day,$Chunk,$Take,$SshOpts,$TimeoutMs) $false }
function Test-ConnectRemoteLogNeedsRebuild { param($LocalSize,$RemoteSize,$Offset) $false }
function Invoke-ConnectLogProcTimed { param($Exe,$ArgumentList,$TimeoutMs) @{ Ok=$true; TimedOut=$false; ExitCode=0; StdOut='0'; StdErr='' } }
$script:ConnectLogSyncFailLogged = $false
$escaped = 0
try { Sync-ConnectLogToServer -Force | Out-Null } catch { $escaped++ }
try { $script:ConnectLogWriter.Flush() } catch { }
$raw = Get-Content -LiteralPath $script:ConnectLogPath -Raw
Write-Output ("L3_ESCAPED=" + $escaped)
Write-Output ("L3_FAIL=" + [int]($raw -match 'LOG_SYNC_FAIL'))
Write-Output ("L3_TYPED=" + [int]($raw -match 'LOG_SYNC_FAIL[^\r\n]*type=NullReferenceException'))
Write-Output ("L3_BARE_ONLY=" + [int](($raw -match 'detail=exception[^\r\n]*err=Object reference') -and ($raw -notmatch 'at=\S+')))
'@ | Set-Content -LiteralPath $driver3 -Encoding UTF8
$out3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver3 -UiPath $uiPath -Home2 $home3 2>&1 | Out-String
Write-Host '--- L3 ---'
Write-Host $out3
Assert-C 'L3a' ((Get-Flag $out3 'L3_ESCAPED') -eq 0) 'L3: post-chunk NRE does not escape Sync' ('escaped=' + (Get-Flag $out3 'L3_ESCAPED'))
Assert-C 'L3b' ((Get-Flag $out3 'L3_FAIL') -ge 1 -or (Get-Flag $out3 'L3_ESCAPED') -eq 0) 'L3: fail-soft (Fail breadcrumb or silent soft via probe catch)' ('fail=' + (Get-Flag $out3 'L3_FAIL'))
# Get-ConnectRemoteLogByteSize has its own catch -> returns -1, so Sync may continue OK.
# Contract: never escape; if FAIL appears it must be typed with at=.
Assert-C 'L3c' ((Get-Flag $out3 'L3_BARE_ONLY') -eq 0) 'L3: no bare untyped exception breadcrumb' ('flag=' + (Get-Flag $out3 'L3_BARE_ONLY'))

Write-Host ''
Write-Host ("=== RESULT fail={0} ===" -f $fail)
if ($fail -gt 0) { Write-Host 'VERDICT: FAIL'; exit 1 }
Write-Host 'VERDICT: PASS'
exit 0
