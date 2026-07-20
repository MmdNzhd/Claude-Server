Set-Location 'D:\Smart\Claude-Code-Server'
$ErrorActionPreference='Stop'
$lock='scripts\tmp\.FIX-CRITICAL.lock'
'locking' | Set-Content $lock

# ===== git-mode.sh =====
$g='scripts\client\git-mode.sh'
$bytes=[IO.File]::ReadAllBytes($g)
# detect BOM/utf8
$gs=[IO.File]::ReadAllText($g)
$gs=$gs.Replace('for i in $(seq 1 4); do','for i in $(seq 1 12); do')
$oldRecover="    timeout 30 sshx `"`$CM recover-one '`$id' 2>/dev/null || timeout 30 sshx `"`$CM recover-if-needed '`$id' 2>/dev/null || timeout 30 sshx `"`$CM recover`" 2>/dev/null || true"
# use regex replace on the broken pattern
$gs=[regex]::Replace($gs,
  '(?m)^[ \t]*timeout 30 sshx "\$CM recover-one ''\$id'' 2>/dev/null \|\| timeout 30 sshx "\$CM recover-if-needed ''\$id'' 2>/dev/null \|\| timeout 30 sshx "\$CM recover" 2>/dev/null \|\| true\s*$',
  '    sshx "timeout 30 $CM recover-one ''$id'' 2>/dev/null || timeout 30 $CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 $CM recover 2>/dev/null" 2>/dev/null || true')
if($gs -match 'timeout 30 sshx "\$CM recover-one'){
  # fallback line-based
  $lines=$gs -split "`n",-1
  for($i=0;$i -lt $lines.Length;$i++){
    if($lines[$i] -match 'timeout 30 sshx "\$CM recover-one'){
      $lines[$i]='    sshx "timeout 30 $CM recover-one ''$id'' 2>/dev/null || timeout 30 $CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 $CM recover 2>/dev/null" 2>/dev/null || true'
    }
  }
  $gs=$lines -join "`n"
}
$utf8=New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText((Resolve-Path $g), $gs, $utf8)

# ===== git-mode.ps1 banner_miss + ensure =====
$p='scripts\client\git-mode.ps1'
$ps=[IO.File]::ReadAllText($p)

# Replace soft_fail banner_miss block that resets count - find unique old pattern
$oldBanner=@'
                    Write-GitModeLog "TUNNEL_SYNC soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
                    $script:TunnelSoftFailCount = 0
                    $script:TunnelSyncFailCount = 0
                    return $true
'@
$newBanner=@'
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
'@
if($ps.Contains($oldBanner)){ $ps=$ps.Replace($oldBanner,$newBanner); 'patched banner block A' }
else {
  # alternate older pattern without SoftFailCount=0 line together
  $old2=@'
                    Write-GitModeLog "TUNNEL_SYNC soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
                    $script:TunnelSyncFailCount = 0
                    return $true
'@
  if($ps.Contains($old2)){ $ps=$ps.Replace($old2,$newBanner); 'patched banner block B' } else { 'WARN banner pattern not found - check manually' }
}

$oldEnsure=@'
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
            $script:TunnelSoftFailCount = 0
            $script:TunnelSyncFailCount = 0
            $TunnelReused.Value = $true
            return $true
'@
$newEnsure=@'
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
'@
if($ps.Contains($oldEnsure)){ $ps=$ps.Replace($oldEnsure,$newEnsure); 'patched ensure A' }
else {
  $oldE2=@'
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
            $script:TunnelSyncFailCount = 0
            $TunnelReused.Value = $true
            return $true
'@
  if($ps.Contains($oldE2)){ $ps=$ps.Replace($oldE2,$newEnsure); 'patched ensure B' }
  else {
    $oldE3=@'
        if ($tcpOpen) {
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
            $script:TunnelSoftFailCount = 0
            $TunnelReused.Value = $true
            return $true
        }
'@
    if($ps.Contains($oldE3)){ $ps=$ps.Replace($oldE3, @"
        if (`$tcpOpen) {
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=`$(`$BgTunnel.Value.Id) port=`$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
        }
"@); 'patched ensure C' } else { 'WARN ensure pattern not found' }
  }
}

[IO.File]::WriteAllText((Resolve-Path $p), $ps, $utf8)

# ===== connect.ps1 strip fancy quotes =====
$c='scripts\client\windows\connect.ps1'
$ct=[IO.File]::ReadAllText($c)
$ct2=$ct -replace '[\u201C\u201D]','"' -replace '[\u2018\u2019]',"'" -replace '[\u2014\u2013\u2012]','-'
[IO.File]::WriteAllText((Resolve-Path $c), $ct2, $utf8)

# ===== VERIFY =====
$gs=[IO.File]::ReadAllText($g)
$ps=[IO.File]::ReadAllText($p)
$ct=[IO.File]::ReadAllText($c)
$ok=$true
function Must($n,$cond){ if($cond){"PASS $n"} else { "FAIL $n"; $script:ok=$false } }
Must 'seq12' (($gs -match 'seq 1 12') -and ($gs -notmatch 'seq 1 4'))
Must 'recover-clean' ($gs -notmatch 'timeout 30 sshx "\$CM recover-one')
Must 'recover-has-sshx-timeout-cm' ($gs -match 'sshx "timeout 30 \$CM recover-one')
Must 'banner-budget' ($ps -match 'banner_miss_tcp_open_budget')
Must 'ensure-reseed' ($ps -match 'action=reseed')
Must 'curly' ($ct -notmatch '[\u201C\u201D\u2018\u2019]')
"OVERALL_STATIC=$(if($ok){'PASS'}else{'FAIL'})"
'ATOMIC_FIX_DONE' | Set-Content 'scripts\tmp\ATOMIC-CRITICAL-FIXED.md'
Get-Item $g,$p,$c | Format-Table Name,Length,LastWriteTime
