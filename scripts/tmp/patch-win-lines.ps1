Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false
$pPath=(Resolve-Path 'scripts\client\git-mode.ps1').Path
$lines=[System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]][IO.File]::ReadAllLines($pPath))

function Show($a,$b){ for($i=$a;$i -le $b;$i++){ if($i -ge 1 -and $i -le $lines.Count){ '{0}|{1}' -f $i, $lines[$i-1] } } }

Write-Output 'BEFORE SYNC banner region:'
# find banner_miss line numbers
$idxs=@()
for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match 'banner_miss_tcp_open'){ $idxs+=($i+1) } }
"hits=$($idxs -join ',')"
foreach($n in $idxs){ Show ($n-5) ($n+12); '---' }

# Patch Sync-SessionTunnel: find line with TUNNEL_SYNC soft_fail ... banner_miss without count=
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'TUNNEL_SYNC soft_fail pid=.*reason=banner_miss_tcp_open' -and $lines[$i] -notmatch 'count='){
    # look ahead for return $true within 8 lines and SoftFailCount=0
    $end=[Math]::Min($i+10,$lines.Count-1)
    $block=($lines[$i..$end] -join "`n")
    if($block -match 'return \$true' -and $block -notmatch 'banner_miss_tcp_open_budget'){
      # replace from this log line through return $true
      $j=$i
      while($j -lt $lines.Count -and $lines[$j] -notmatch 'return \$true'){ $j++ }
      if($j -lt $lines.Count){
        $indent=($lines[$i] -replace '^(\s*).*','$1')
        $new=@(
          "${indent}`$script:TunnelSoftFailCount++",
          "${indent}Write-GitModeLog `"TUNNEL_SYNC soft_fail count=`$script:TunnelSoftFailCount/6 pid=`$(`$BgTunnel.Value.Id) port=`$Port reason=banner_miss_tcp_open`" 'WARN'",
          "${indent}`$script:TunnelSyncFailCount = 0",
          "${indent}if (`$script:TunnelSoftFailCount -ge 6) {",
          "${indent}    Write-GitModeLog `"TUNNEL_DROP pid=`$(`$BgTunnel.Value.Id) port=`$Port reason=banner_miss_tcp_open_budget count=`$script:TunnelSoftFailCount`" 'WARN'",
          "${indent}    Release-StaleTunnelPort",
          "${indent}    `$script:TunnelSoftFailCount = 0",
          "${indent}    return `$false",
          "${indent}}",
          "${indent}return `$true"
        )
        # also remove SoftFailCount=0 lines between i and j if present
        $countToRemove=$j-$i+1
        $lines.RemoveRange($i,$countToRemove)
        for($k=$new.Count-1;$k -ge 0;$k--){ $lines.Insert($i,$new[$k]) }
        'patched SYNC banner at ' + ($i+1)
        break
      }
    }
  }
}

# Patch Ensure: soft_fail banner_miss that returns success
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'ENSURE_TUNNEL soft_fail.*banner_miss_tcp_open' -and $lines[$i] -notmatch 'action=reseed'){
    $end=[Math]::Min($i+8,$lines.Count-1)
    $block=($lines[$i..$end] -join "`n")
    if($block -match 'TunnelReused\.Value = \$true' -or $block -match 'return \$true'){
      $j=$i
      while($j -lt $lines.Count -and $lines[$j] -notmatch 'return \$true'){ $j++ }
      $indent=($lines[$i] -replace '^(\s*).*','$1')
      $new=@(
        "${indent}# Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.",
        "${indent}Write-GitModeLog `"ENSURE_TUNNEL soft_fail pid=`$(`$BgTunnel.Value.Id) port=`$Port reason=banner_miss_tcp_open action=reseed`" 'WARN'",
        "${indent}# Fall through to kill stale bg + reseed below."
      )
      if($j -lt $lines.Count -and $lines[$j] -match 'return \$true'){
        $countToRemove=$j-$i+1
        $lines.RemoveRange($i,$countToRemove)
        for($k=$new.Count-1;$k -ge 0;$k--){ $lines.Insert($i,$new[$k]) }
        'patched ENSURE at ' + ($i+1)
        break
      } elseif($block -match 'TunnelReused'){
        # find return true
        $j2=$i; while($j2 -lt $lines.Count -and $lines[$j2] -notmatch 'return \$true'){ $j2++ }
        if($j2 -lt $lines.Count){
          $countToRemove=$j2-$i+1
          $lines.RemoveRange($i,$countToRemove)
          for($k=$new.Count-1;$k -ge 0;$k--){ $lines.Insert($i,$new[$k]) }
          'patched ENSURE-B at ' + ($i+1)
          break
        }
      }
    } else {
      # just rewrite the log line to include action=reseed and ensure no return true immediately after SoftFail reset
      $lines[$i]=($lines[$i] -replace 'reason=banner_miss_tcp_open"','reason=banner_miss_tcp_open action=reseed"')
      'rewrote ENSURE log line'
    }
  }
}

[IO.File]::WriteAllLines($pPath,$lines.ToArray(),$utf8)

$ps=[IO.File]::ReadAllText($pPath)
"budget=$($ps -match 'banner_miss_tcp_open_budget') reseed=$($ps -match 'action=reseed')"
Select-String -Path $pPath -Pattern 'banner_miss' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }
