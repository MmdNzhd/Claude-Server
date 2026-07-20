$ErrorActionPreference='Continue'
Write-Output '=== version ==='
Get-Content 'scripts\client\windows\connect-version.txt'
Select-String -Path 'scripts\client\windows\connect.ps1','scripts\client\mac\connect.sh' -Pattern 'ConnectVersion|CONNECT_VERSION' |
  Select-Object -First 4 | ForEach-Object { $_.Line.Trim() }

Write-Output '=== markers ==='
$checks = @{
  'ps1-single-connect' = @{ Path='scripts\client\git-mode.ps1'; Pat='read -r -t 2 line <&3' }
  'ps1-no-double-nc' = @{ Path='scripts\client\git-mode.ps1'; Pat='timeout 2 nc 127.0.0.1' ; Neg=$true }
  'ps1-positive-cache' = @{ Path='scripts\client\git-mode.ps1'; Pat='Positive cache only' }
  'ps1-reattach-first' = @{ Path='scripts\client\git-mode.ps1'; Pat='Reattach BEFORE banner check' }
  'ps1-soft-tcp' = @{ Path='scripts\client\git-mode.ps1'; Pat='banner_miss_tcp_open' }
  'ps1-maxstartups' = @{ Path='scripts\client\git-mode.ps1'; Pat='reason=maxstartups' }
  'ps1-tunnelSyncOk' = @{ Path='scripts\client\windows\connect.ps1'; Pat='tunnelSyncOk' }
  'diag-effectively' = @{ Path='scripts\client\connect-diagnostic.ps1'; Pat='tunnelEffectivelyUp' }
  'diag-LocalPortOpen' = @{ Path='scripts\client\connect-diagnostic.ps1'; Pat='LocalPortOpen' }
  'sh-single-connect' = @{ Path='scripts\client\git-mode.sh'; Pat='read -r -t 2 line <&3' }
  'sh-tcp-open' = @{ Path='scripts\client\git-mode.sh'; Pat='tunnel_tcp_open' }
  'sh-soft-tcp' = @{ Path='scripts\client\git-mode.sh'; Pat='banner_miss_tcp_open' }
}
foreach ($k in $checks.Keys) {
  $c = $checks[$k]
  $hit = Select-String -Path $c.Path -Pattern $c.Pat -SimpleMatch -Quiet
  if ($c.Neg) {
    if ($hit) { "FAIL $k still has $($c.Pat)" } else { "PASS $k (absent)" }
  } else {
    if ($hit) { "PASS $k" } else { "FAIL $k missing $($c.Pat)" }
  }
}

Write-Output '=== Get-TunnelBanner probe line (escaping) ==='
Select-String -Path 'scripts\client\git-mode.ps1' -Pattern 'TUNNEL_BANNER_BEGIN|printf %s|dev/tcp' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Output '=== Parse connect.ps1 ==='
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\connect.ps1'), [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { "PARSE ERR: $_" } } else { 'connect.ps1 parse OK' }
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\git-mode.ps1'), [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { "PARSE ERR: $_" } } else { 'git-mode.ps1 parse OK' }
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\connect-diagnostic.ps1'), [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { "PARSE ERR: $_" } } else { 'connect-diagnostic.ps1 parse OK' }

# Show the actual SshX string as PowerShell would expand $line
$line = Get-Content 'scripts\client\git-mode.ps1' | Where-Object { $_ -match 'printf %s' } | Select-Object -First 1
Write-Output "RAW_PROBE=$line"
