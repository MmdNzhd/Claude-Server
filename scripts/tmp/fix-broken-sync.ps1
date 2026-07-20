Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false
$pPath=(Resolve-Path 'scripts\client\git-mode.ps1').Path
$text=[IO.File]::ReadAllText($pPath)

# Fix the broken banner_miss / else region between "if ($tcpOpen) {" after probe and the TRACE throttle
$broken=@'
                if ($tcpOpen) {
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
                    }
                    Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port banner=$probeBanner reason=bg_alive_forward_dead misses=$script:TunnelSyncFailCount" 'WARN'
                    Release-StaleTunnelPort
                    $script:TunnelSoftFailCount = 0
                    return $false
                }
            } else {
                $script:TunnelSyncFailCount = 0
                $script:TunnelSoftFailCount = 0
            }
'@

$fixed=@'
                if ($tcpOpen) {
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
                } else {
                    $script:TunnelSyncFailCount++
                    $probeBanner = $script:TunnelBannerCacheBanner
                    if ($script:TunnelSyncFailCount -lt 3) {
                        $script:LastForwardProbeAt = (Get-Date).AddSeconds(-30)
                        Write-GitModeLog "TUNNEL_SYNC miss=$script:TunnelSyncFailCount/3 pid=$($BgTunnel.Value.Id) port=$Port reason=bg_alive_forward_dead" 'DEBUG'
                        return $true
                    }
                    Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port banner=$probeBanner reason=bg_alive_forward_dead misses=$script:TunnelSyncFailCount" 'WARN'
                    Release-StaleTunnelPort
                    $script:TunnelSoftFailCount = 0
                    return $false
                }
            } else {
                $script:TunnelSyncFailCount = 0
                $script:TunnelSoftFailCount = 0
            }
'@

if($text.Contains($broken)){ $text=$text.Replace($broken,$fixed); 'fixed broken sync block' } else { 'broken block not exact - try normalize newlines'; ($text.Contains(($broken -replace "`r`n","`n"))) }

# Fix Ensure: remove TunnelReused=true before reseed; use elseif for recent_success
$ensBroken=@'
        if ($tcpOpen) {
            $TunnelReused.Value = $true
            $script:TunnelSyncFailCount = 0
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
        }
        if ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
'@
$ensFixed=@'
        if ($tcpOpen) {
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            Write-GitModeLog "ENSURE_TUNNEL soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed" 'WARN'
            # Fall through to kill stale bg + reseed below.
        } elseif ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
'@
if($text.Contains($ensBroken)){ $text=$text.Replace($ensBroken,$ensFixed); 'fixed ensure' } else { 'ensure pattern miss' }

[IO.File]::WriteAllText($pPath,$text,$utf8)

$err=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($pPath,[ref]$null,[ref]$err)
"parse_errors=$($err.Count)"
if($err){ $err | Select-Object -First 3 | ForEach-Object { $_.ToString() } }

$ps=[IO.File]::ReadAllText($pPath)
"budget=$($ps -match 'banner_miss_tcp_open_budget') reseed=$($ps -match 'action=reseed')"

# show fixed region
$lines=Get-Content $pPath
500..545 | ForEach-Object { '{0}|{1}' -f $_, $lines[$_-1] }
