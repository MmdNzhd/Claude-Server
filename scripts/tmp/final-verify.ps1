$ErrorActionPreference='Continue'
Write-Output "version=$(Get-Content scripts\client\windows\connect-version.txt -Raw)"
$checks = @(
  @{n='nc-probe-ps1'; p='scripts\client\git-mode.ps1'; pat='timeout 3 nc -w 2 127.0.0.1 \$Port'},
  @{n='no-double-ps1'; p='scripts\client\git-mode.ps1'; pat='timeout 2 nc 127.0.0.1 \$Port'; neg=$true},
  @{n='nc-probe-sh'; p='scripts\client\git-mode.sh'; pat='timeout 3 nc -w 2 127.0.0.1 \${PORT}'},
  @{n='tunnelSyncOk'; p='scripts\client\windows\connect.ps1'; pat='tunnelSyncOk'},
  @{n='reattach'; p='scripts\client\git-mode.ps1'; pat='Reattach BEFORE'},
  @{n='soft-tcp'; p='scripts\client\git-mode.ps1'; pat='banner_miss_tcp_open'},
  @{n='diag'; p='scripts\client\connect-diagnostic.ps1'; pat='tunnelEffectivelyUp'},
  @{n='ver'; p='scripts\client\windows\connect.ps1'; pat="ConnectVersion = '20260717.5'"}
)
foreach ($c in $checks) {
  $hit = Select-String -Path $c.p -Pattern $c.pat -Quiet
  if ($c.neg) {
    if ($hit) { "FAIL $($c.n)" } else { "PASS $($c.n)" }
  } else {
    if ($hit) { "PASS $($c.n)" } else { "FAIL $($c.n) missing $($c.pat)" }
  }
}
$errs=$null
foreach ($f in @('scripts\client\git-mode.ps1','scripts\client\windows\connect.ps1','scripts\client\connect-diagnostic.ps1')) {
  $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$errs)
  if ($errs) { "PARSE_FAIL $f : $($errs[0])" } else { "PARSE_OK $f" }
}
# show probe lines
Select-String -Path 'scripts\client\git-mode.ps1','scripts\client\git-mode.sh' -Pattern 'nc -w 2' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber): $($_.Line.Trim())" }
