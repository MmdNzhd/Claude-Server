#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location D:\Smart\Claude-Code-Server
$utf8 = New-Object System.Text.UTF8Encoding $false

# 1) session-log-contracts
$sl = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/tests/test-session-log-contracts.ps1'))
$old = "Assert (`$ui -match 'MULTI_INSTANCE: allowed') 'multi-instance allowed (no global mutex)'"
$new = "Assert (`$ui -match 'SINGLE_INSTANCE|Global\\ClaudeConnect') 'single-instance mutex (Global\\ClaudeConnect)'"
if ($sl.Contains("MULTI_INSTANCE: allowed")) {
  $sl2 = $sl.Replace($old, $new)
  if ($sl2 -eq $sl) {
    # try without escape differences
    $sl2 = [regex]::Replace($sl, "Assert \(\`$ui -match 'MULTI_INSTANCE: allowed'\) '[^']*'", $new)
  }
  if ($sl2 -eq $sl) { throw 'session-log replace failed' }
  [IO.File]::WriteAllText((Resolve-Path 'scripts/client/tests/test-session-log-contracts.ps1'), $sl2, $utf8)
  Write-Host 'OK session-log-contracts' -ForegroundColor Green
} else {
  Write-Host 'SKIP session-log already fixed' -ForegroundColor Yellow
}

# 2) pipeline hide assert
$pipe = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/tests/test-connect-pipeline.ps1'))
$oldP = 'Assert ($mount -match ''\$n -lt 3'') "claude-mount retries git rename 3x"'
# actual file content uses double-quoted message
if ($pipe -match 'retries git rename 3x') {
  $pipe2 = [regex]::Replace($pipe, 'Assert \(\$mount -match ''\\\$n -lt 3''\) "claude-mount retries git rename 3x"', 'Assert ($mount -match ''\$n -lt 2'') "claude-mount git hide fail-fast (<=2 attempts)"')
  if ($pipe2 -eq $pipe) {
    $pipe2 = $pipe.Replace('Assert ($mount -match ''\$n -lt 3'') "claude-mount retries git rename 3x"', 'Assert ($mount -match ''\$n -lt 2'') "claude-mount git hide fail-fast (<=2 attempts)"')
  }
  if ($pipe2 -eq $pipe) {
    # raw from Get-Content style
    $pipe2 = $pipe.Replace('\$n -lt 3'') "claude-mount retries git rename 3x"', '\$n -lt 2'') "claude-mount git hide fail-fast (<=2 attempts)"')
  }
  if ($pipe2 -eq $pipe) { 
    Write-Host 'DUMP pipeline around assert:' -ForegroundColor Yellow
    $lines = $pipe -split "`n"
    for ($i=0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match 'lt 3|rename 3x') { Write-Host ("{0}:[{1}]" -f ($i+1), $lines[$i]) }
    }
    throw 'pipeline replace failed'
  }
  [IO.File]::WriteAllText((Resolve-Path 'scripts/client/tests/test-connect-pipeline.ps1'), $pipe2, $utf8)
  Write-Host 'OK pipeline hide assert' -ForegroundColor Green
} else {
  Write-Host 'SKIP pipeline already fixed' -ForegroundColor Yellow
}

# 3) Opening Cursor: ensure false launch => StepFail (verify code)
$win = Get-Content 'scripts/client/windows/connect.ps1' -Raw
$ok = ($win -match '(?s)if \(-not \(Launch-RemoteEditor[\s\S]{0,200}StepFail')
Write-Host ("Launch->StepFail present: {0}" -f $ok)

# 4) silent update stamp only on success — quick check
$ui = Get-Content 'scripts/client/connect-ui.ps1' -Raw
$fn = [regex]::Match($ui, '(?s)function Invoke-ConnectSilentUpdateCheck \{.{0,3500}')
Write-Host '--- silent update stamp logic excerpt ---'
if ($fn.Success) {
  $body = $fn.Value
  $hasFinallyStamp = $body -match 'finally[\s\S]{0,400}last-update-check'
  $stampInFinally = $body -match '(?s)finally\s*\{[^}]*WriteAllText\(\$stateFile'
  Write-Host ("stamp_in_finally_unconditional={0}" -f $stampInFinally)
  # show whether stamp gated
  Select-String -Path scripts/client/connect-ui.ps1 -Pattern 'last-update-check|WriteAllText\(\$stateFile|shouldStamp|stamp' | Select-Object -First 15 | ForEach-Object {
    Write-Host ("{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
  }
}

Write-Host 'Done fixes.'
