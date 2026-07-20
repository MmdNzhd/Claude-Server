Set-Location 'D:\Smart\Claude-Code-Server'
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding $false

# --- git-mode.sh ---
$gPath=(Resolve-Path 'scripts\client\git-mode.sh').Path
$gs=[IO.File]::ReadAllText($gPath)
$gs=$gs.Replace('for i in $(seq 1 4); do','for i in $(seq 1 12); do')
$lines=$gs -split "`n",-1
for($i=0;$i -lt $lines.Length;$i++){
  if($lines[$i] -match 'timeout 30 sshx "\$CM recover-one'){
    $lines[$i]='    sshx "timeout 30 $CM recover-one ''$id'' 2>/dev/null || timeout 30 $CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 $CM recover 2>/dev/null" 2>/dev/null || true'
  }
}
$gs=$lines -join "`n"
[IO.File]::WriteAllText($gPath,$gs,$utf8)

# --- git-mode.ps1: read current banner/ensure and patch if missing ---
$pPath=(Resolve-Path 'scripts\client\git-mode.ps1').Path
$ps=[IO.File]::ReadAllText($pPath)
if($ps -notmatch 'banner_miss_tcp_open_budget'){
  # replace simple banner_miss return true patterns
  $ps=[regex]::Replace($ps,
    '(?ms)(if \(\$tcpOpen\) \{\s*)Write-GitModeLog "TUNNEL_SYNC soft_fail pid=\$\(\$BgTunnel\.Value\.Id\) port=\$Port reason=banner_miss_tcp_open" ''WARN''\s+\$script:TunnelSoftFailCount = 0\s+\$script:TunnelSyncFailCount = 0\s+return \$true',
    '${1}$script:TunnelSoftFailCount++`r`n                    Write-GitModeLog "TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" ''WARN''`r`n                    $script:TunnelSyncFailCount = 0`r`n                    if ($script:TunnelSoftFailCount -ge 6) {`r`n                        Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open_budget count=$script:TunnelSoftFailCount" ''WARN''`r`n                        Release-StaleTunnelPort`r`n                        $script:TunnelSoftFailCount = 0`r`n                        return $false`r`n                    }`r`n                    return $true')
  if($ps -notmatch 'banner_miss_tcp_open_budget'){
    $ps=[regex]::Replace($ps,
      'Write-GitModeLog "TUNNEL_SYNC soft_fail pid=\$\(\$BgTunnel\.Value\.Id\) port=\$Port reason=banner_miss_tcp_open" ''WARN''\s+\$script:TunnelSyncFailCount = 0\s+return \$true',
      @'
$script:TunnelSoftFailCount++
                    Write-GitModeLog "TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
                    $script:TunnelSyncFailCount = 0
                    if ($script:TunnelSoftFailCount -ge 6) {
                        Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open_budget count=$script:TunnelSoftFailCount" 'WARN'
                        Release-StaleTunnelPort
                        $script:TunnelSoftFailCount = 0
                        return $false
                    }
                    return $true
'@)
  }
  'banner patched try1'
}
if($ps -notmatch 'action=reseed'){
  $ps=[regex]::Replace($ps,
    '(?ms)if \(\$tcpOpen\) \{\s*Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=\$\(\$BgTunnel\.Value\.Id\) port=\$Port reason=banner_miss_tcp_open" ''WARN''\s+\$script:TunnelSoftFailCount = 0\s+\$script:TunnelSyncFailCount = 0\s+\$TunnelReused\.Value = \$true\s+return \$true\s*\}',
    @'
if ($tcpOpen) {
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
        }
'@)
  if($ps -notmatch 'action=reseed'){
    $ps=[regex]::Replace($ps,
      'Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=\$\(\$BgTunnel\.Value\.Id\) port=\$Port reason=banner_miss_tcp_open" ''WARN''\s+\$script:TunnelSyncFailCount = 0\s+\$TunnelReused\.Value = \$true\s+return \$true',
      @'
Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
'@)
  }
  'ensure patched try1'
}
[IO.File]::WriteAllText($pPath,$ps,$utf8)

# connect curly
$cPath=(Resolve-Path 'scripts\client\windows\connect.ps1').Path
$ct=[IO.File]::ReadAllText($cPath)
$ct=$ct -replace '[\u201C\u201D]','"' -replace '[\u2018\u2019]',"'" -replace '[\u2014\u2013\u2012]','-'
[IO.File]::WriteAllText($cPath,$ct,$utf8)

# verify
$gs=[IO.File]::ReadAllText($gPath)
$ps=[IO.File]::ReadAllText($pPath)
$ct=[IO.File]::ReadAllText($cPath)
$ok=$true
function M($n,$c){ if($c){"PASS $n"}else{"FAIL $n"; $script:ok=$false} }
M 'seq12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
M 'recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
M 'budget' ($ps -match 'banner_miss_tcp_open_budget')
M 'reseed' ($ps -match 'action=reseed')
M 'curly' ($ct -notmatch '[\u201C\u201D\u2018\u2019]')
"OVERALL=$(if($ok){'PASS'}else{'FAIL'})"

# dump failing context if needed
if(-not $ok){
  Select-String -Path $gPath -Pattern 'seq 1 |recover-one' | ForEach-Object {"SH:$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))"}
  Select-String -Path $pPath -Pattern 'banner_miss' | ForEach-Object {"PS:$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))"}
}

# run tests if static pass
if($ok){
  $p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe-re.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\pipe-re.err'
  [void]$p.WaitForExit(120000)
  "pipeline_exit=$($p.ExitCode)"
  Select-String scripts\tmp\pipe-re.txt -Pattern 'FAIL |All tests passed|failed\.' | ForEach-Object Line
  $p2=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','D:\Smart\Claude-Code-Server\scripts\client\tests\test-git-mode-deep.ps1' -WorkingDirectory 'D:\Smart\Claude-Code-Server\scripts\client\tests' -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\gm-re.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\gm-re.err'
  [void]$p2.WaitForExit(120000)
  "gitmode_exit=$($p2.ExitCode)"
  Select-String scripts\tmp\gm-re.txt -Pattern 'FAIL |All deep|failed' | Select-Object -Last 3 | ForEach-Object Line
  # post-test lock check
  Start-Sleep 1
  $gs=[IO.File]::ReadAllText($gPath)
  $ps=[IO.File]::ReadAllText($pPath)
  M 'post-seq' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
  M 'post-recover' ($gs -notmatch 'timeout 30 sshx "\$CM recover-one')
  M 'post-budget' ($ps -match 'banner_miss_tcp_open_budget')
  M 'post-reseed' ($ps -match 'action=reseed')
}
