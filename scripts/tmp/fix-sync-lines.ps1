Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false
$pPath=(Resolve-Path 'scripts\client\git-mode.ps1').Path
$lines=[System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]][IO.File]::ReadAllLines($pPath))

# Replace lines 505-521 (1-based) with correct if/else
# Find start: line matching 'if ($tcpOpen)' after probe that is followed by TunnelSoftFailCount++ and banner_miss
$start=-1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match '^\s+if \(\$tcpOpen\) \{\s*$' -and $i+2 -lt $lines.Count -and $lines[$i+1] -match 'TunnelSoftFailCount\+\+' -and $lines[$i+2] -match 'banner_miss_tcp_open'){
    $start=$i; break
  }
}
"start_idx=$start line=$($start+1)"
if($start -lt 0){ throw 'start not found' }

# find the closing of this broken section: after return $false that follows orphan brace, the line '                }' then '            } else {'
# From start, find until we hit '            } else {' that resets both fail counts (probeUp else)
$end=-1
for($i=$start;$i -lt [Math]::Min($start+40,$lines.Count);$i++){
  if($lines[$i] -match '^\s+\} else \{\s*$' -and $i+1 -lt $lines.Count -and $lines[$i+1] -match 'TunnelSyncFailCount = 0' -and $lines[$i+2] -match 'TunnelSoftFailCount = 0'){
    $end=$i-1; break  # end is line before probeUp else
  }
}
"end_idx=$end line=$($end+1)"
if($end -lt 0){ throw 'end not found' }

$new=@(
'                if ($tcpOpen) {',
'                    $script:TunnelSoftFailCount++',
'                    Write-GitModeLog "TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" ''WARN''',
'                    $script:TunnelSyncFailCount = 0',
'                    if ($script:TunnelSoftFailCount -ge 6) {',
'                        Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open_budget count=$script:TunnelSoftFailCount" ''WARN''',
'                        Release-StaleTunnelPort',
'                        $script:TunnelSoftFailCount = 0',
'                        return $false',
'                    }',
'                    return $true',
'                } else {',
'                    $script:TunnelSyncFailCount++',
'                    $probeBanner = $script:TunnelBannerCacheBanner',
'                    if ($script:TunnelSyncFailCount -lt 3) {',
'                        $script:LastForwardProbeAt = (Get-Date).AddSeconds(-30)',
'                        Write-GitModeLog "TUNNEL_SYNC miss=$script:TunnelSyncFailCount/3 pid=$($BgTunnel.Value.Id) port=$Port reason=bg_alive_forward_dead" ''DEBUG''',
'                        return $true',
'                    }',
'                    Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port banner=$probeBanner reason=bg_alive_forward_dead misses=$script:TunnelSyncFailCount" ''WARN''',
'                    Release-StaleTunnelPort',
'                    $script:TunnelSoftFailCount = 0',
'                    return $false',
'                }'
)
$count=$end-$start+1
$lines.RemoveRange($start,$count)
for($k=$new.Count-1;$k -ge 0;$k--){ $lines.Insert($start,$new[$k]) }
"replaced $count lines with $($new.Count)"

# Fix Ensure: remove TunnelReused before reseed; change following if to elseif
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'ENSURE_TUNNEL soft_fail.*action=reseed'){
    # look back for TunnelReused in same if ($tcpOpen)
    for($b=[Math]::Max(0,$i-6);$b -lt $i;$b++){
      if($lines[$b] -match 'TunnelReused\.Value = \$true'){ $lines[$b]='            # (no TUNNEL_REUSED on banner miss)'; }
      if($lines[$b] -match 'TunnelSyncFailCount = 0' -and $lines[$b-1] -match 'TunnelReused|no TUNNEL_REUSED'){ $lines[$b]='            # keep sync fail count; fall through to reseed' }
    }
    # next non-empty structural if after closing brace of tcpOpen should be elseif recent_success
    for($a=$i;$a -lt [Math]::Min($i+10,$lines.Count);$a++){
      if($lines[$a] -match '^\s+if \(\$script:LastTunnelSpawnSuccessAt'){
        $lines[$a]=$lines[$a] -replace '^(\s+)if \(','$1} elseif ('
        # but that might double-close - check if tcpOpen already closed
        'check ensure structure around '+($a+1)
        break
      }
    }
    break
  }
}

[IO.File]::WriteAllLines($pPath,$lines.ToArray(),$utf8)

# Re-read and carefully fix ensure block by exact lines
$lines=[System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]][IO.File]::ReadAllLines($pPath))
# find ensure tcpOpen block
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'action=reseed'){
    ShowStart=[Math]::Max(0,$i-8)
    for($s=$ShowStart;$s -le $i+15;$s++){ '{0}|{1}' -f ($s+1), $lines[$s] }
    break
  }
}

$err=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($pPath,[ref]$null,[ref]$err)
"parse_errors=$($err.Count)"
if($err){ $err|%{ $_.ToString() } }
