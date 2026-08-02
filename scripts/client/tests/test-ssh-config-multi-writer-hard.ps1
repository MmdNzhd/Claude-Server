#Requires -Version 5.1
# HARD: concurrent ssh config writers + pubkey Trim must not throw Object[].Trim
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$Pass=0;$Fail=0
function Assert([bool]$c,[string]$m){ if($c){ Write-Host "  PASS  $m" -ForegroundColor Green; $script:Pass++ } else { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:Fail++ } }

Write-Host ''
Write-Host '=== HARD: ssh config multi-writer + pubkey Trim ===' -ForegroundColor Cyan

$cp = Get-ClientFile 'windows\connect.ps1'
$gm = Get-ClientFile 'git-mode.ps1'
$src = Get-Content -LiteralPath $cp -Raw
$gmSrc = Get-Content -LiteralPath $gm -Raw

Assert ($src -match 'function Set-SshHostBlock') 'Set-SshHostBlock defined'
Assert ($gmSrc -match 'ClaudeConnectSshConfigWrite') 'ssh config write mutex in git-mode (shared by all launchers)'
Assert ($gmSrc -match 'function Invoke-WithSshConfigLock') 'Invoke-WithSshConfigLock in git-mode'
Assert ($src -match 'Write-AsciiFileRetry') 'uses Write-AsciiFileRetry path (via git-mode)'
Assert ($gmSrc -match 'function Write-AsciiFileRetry') 'Write-AsciiFileRetry in git-mode'
Assert ($src -match 'Get-Content -LiteralPath \"\$keyA\.pub\" -Raw') 'pubkey read uses -Raw (no Object[].Trim)'
Assert ($src -notmatch '\(Get-Content \"\$keyA\.pub\"\)\.Trim\(\)') 'old Object[].Trim pubkey pattern gone'
Assert ($src -match 'Set-SshHostBlock -CfgPath \$sshCfg') 'auth/fix paths use Set-SshHostBlock'
Assert ($src -match 'user@IP|RemoteUser\}\@\{\$ServerIP|verifyEc') 'AUTH verify has IP fallback / retry'

# Regressions that reintroduce the UNHANDLED crash under a click-storm.
Assert ($src -notmatch 'Add-Content -Path \$sshCfg') 'no unlocked Add-Content on ssh config'
Assert ($src -notmatch 'Add-Content -Path \$SshCfgPath') 'no unlocked Add-Content on SshCfgPath'
Assert ($src -notmatch 'New-Item -ItemType File -Path \$sshCfg') 'no TOCTOU pre-create of ssh config'
$fnWriteSrc = Get-FunctionSource -Content $gmSrc -Name 'Write-AsciiFileRetry'
$replaceIdx = $fnWriteSrc.IndexOf('[System.IO.File]::Replace($tmp, $Path')
$copyIdx = $fnWriteSrc.IndexOf('Copy-Item -LiteralPath $tmp -Destination $Path')
Assert ($replaceIdx -ge 0) 'Write-AsciiFileRetry swaps temp in atomically'
Assert (($copyIdx -lt 0) -or ($copyIdx -gt $replaceIdx)) 'non-atomic Copy-Item is only a last-resort fallback, never the primary write'
# $null coerces to '' for [string] parameters, which makes File.Replace throw "path is not of a
# legal form" - the backup argument must be a real null.
Assert ($fnWriteSrc -match '\[NullString\]::Value') 'File.Replace gets a real null backup path'
# 'Local\' is the per-logon-session namespace and is shared across UAC elevation; 'Global\' needs
# SeCreateGlobalPrivilege (absent from a filtered admin token) so it must not be the primary name.
$localIdx = $gmSrc.IndexOf("Local\ClaudeConnectSshConfigWrite")
$globalIdx = $gmSrc.IndexOf("Global\ClaudeConnectSshConfigWrite")
Assert (($localIdx -ge 0) -and ($globalIdx -gt $localIdx)) 'mutex tries Local\ before Global\ (elevated + plain UI share one lock)'

# Live: 6 concurrent Set-SshHostBlock against temp config
$fnSet = Get-FunctionSource -Content $src -Name 'Set-SshHostBlock'
$fnMtx = Get-FunctionSource -Content $gmSrc -Name 'Get-SshConfigWriteMutex'
$fnLock = Get-FunctionSource -Content $gmSrc -Name 'Invoke-WithSshConfigLock'
$fnWrite = Get-FunctionSource -Content $gmSrc -Name 'Write-AsciiFileRetry'
$fnSan = Get-FunctionSource -Content $gmSrc -Name 'Sanitize-SshAliasConfig'
$fnRemove = Get-FunctionSource -Content $src -Name 'Remove-SshHostBlock'
Assert ($fnSet -and $fnMtx -and $fnLock -and $fnWrite -and $fnSan -and $fnRemove) 'extracted Set/Remove/Mutex/Lock/Write/Sanitize helpers'
if (-not ($fnSet -and $fnMtx -and $fnLock -and $fnWrite -and $fnSan -and $fnRemove)) { Write-Host "RESULT: $Pass pass / $Fail fail"; exit 1 }

$root = Join-Path $env:TEMP ("cc-ssh-cfg-race-{0}" -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$cfg = Join-Path $root 'config'
Set-Content -LiteralPath $cfg -Value "Host keepme`n    HostName 1.2.3.4`n" -Encoding ASCII

$chunk = @"
`$ErrorActionPreference='Stop'
$fnWrite
$fnMtx
$fnLock
$fnSan
$fnSet
$fnRemove
"@

try {
  # Writers alternate Set/Remove so the alias block is created and deleted concurrently - the
  # exact click-storm shape that produced "used by another process" from connect.ps1.
  $jobs = 1..6 | ForEach-Object {
    $n = $_
    Start-Job -ScriptBlock {
      param($Chunk,$Cfg,$N)
      try {
        Invoke-Expression $Chunk
        for ($i = 0; $i -lt 12; $i++) {
          Set-SshHostBlock -CfgPath $Cfg -AliasName 'claude-server' -HostName ("10.0.0.$N") -UserName ("user$N")
          if ($i % 4 -eq 3) { Remove-SshHostBlock $Cfg 'claude-server' }
        }
        Set-SshHostBlock -CfgPath $Cfg -AliasName 'claude-server' -HostName ("10.0.0.$N") -UserName ("user$N")
        'ok'
      } catch {
        "ERR:$($_.Exception.Message)"
      }
    } -ArgumentList $chunk, $cfg, $n
  }
  # Reader hammers the config while writers churn: an atomic swap means every successful read is
  # a whole file, never a truncated one, and 'Host keepme' is never lost.
  $reader = Start-Job -ScriptBlock {
    param($Cfg)
    $bad = 0; $reads = 0
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
      try {
        $t = [System.IO.File]::ReadAllText($Cfg)
        $reads++
        if ($t -and ($t -notmatch 'Host keepme')) { $bad++ }
      } catch { }
      Start-Sleep -Milliseconds 5
    }
    "reads=$reads bad=$bad"
  } -ArgumentList $cfg

  $null = Wait-Job $jobs -Timeout 120
  $still = @($jobs | Where-Object { $_.State -eq 'Running' })
  if ($still.Count -gt 0) { $still | Stop-Job -ErrorAction SilentlyContinue }
  $outs = @($jobs | Receive-Job -ErrorAction SilentlyContinue)
  $oks = @($outs | Where-Object { $_ -eq 'ok' })
  $jobErrs = @($outs | Where-Object { $_ -is [string] -and $_ -like 'ERR:*' })
  $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
  Assert ($oks.Count -eq 6) ("6/6 concurrent writers ok (got $($oks.Count); outs=$($outs.Count) still=$($still.Count))")
  Assert ($jobErrs.Count -eq 0) ("no writer threw (errors=$($jobErrs.Count)): " + (($jobErrs | Select-Object -First 1) -join ''))

  $null = Wait-Job $reader -Timeout 30
  $rOut = [string](@($reader | Receive-Job -ErrorAction SilentlyContinue) -join ' ')
  $reader | Remove-Job -Force -ErrorAction SilentlyContinue
  $rBad = if ($rOut -match 'bad=(\d+)') { [int]$matches[1] } else { -1 }
  $rReads = if ($rOut -match 'reads=(\d+)') { [int]$matches[1] } else { 0 }
  Assert ($rReads -gt 0) ("concurrent reader got reads ($rOut)")
  Assert ($rBad -eq 0) ("reader never saw a torn/truncated config ($rOut)")

  # Last writer may have been a Remove mid-storm; settle with one final Set in-parent.
  Invoke-Expression $chunk
  Set-SshHostBlock -CfgPath $cfg -AliasName 'claude-server' -HostName '10.0.0.99' -UserName 'settle'
  $text = Get-Content -LiteralPath $cfg -Raw
  Assert ($text -match 'Host keepme') 'unrelated Host keepme preserved'
  Assert (($text -split "`n" | Where-Object { $_ -match '^\s*Host\s+claude-server\s*$' }).Count -eq 1) 'exactly one claude-server Host block'
  Assert ($text -match 'HostName 10\.0\.0\.\d+') 'claude-server HostName written'
  Assert ($text -match 'StrictHostKeyChecking accept-new') 'alias block kept StrictHostKeyChecking'
  Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.tmp' -ErrorAction SilentlyContinue).Count -eq 0) 'no temp files left behind'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# P1.5 (2026-08-02 audit): multi-Connect click-storm ~21:00 Aug 1 shared the same
# .ssh\config file-lock root cause. The 6-writer storm above IS that shape (near-
# simultaneous Set-SshHostBlock / Remove-SshHostBlock). Extra confirmations:
Assert ($src -match 'Fail-open if an older git-mode\.ps1') 'connect.ps1 documents fail-open mutex when git-mode is stale'
Assert ($gmSrc -match 'function Get-SshConfigWriteMutex') 'Get-SshConfigWriteMutex still defined (mutex fix intact)'
Assert ($gmSrc -match '\[System\.IO\.File\]::Replace') 'File.Replace atomic swap still present (mutex fix intact)'

Write-Host ''
if ($Fail -eq 0) { Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass,$Fail) -ForegroundColor Green; exit 0 }
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass,$Fail) -ForegroundColor Red; exit 1
