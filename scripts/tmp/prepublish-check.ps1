Set-Location D:\Smart\Claude-Code-Server
$ver = (Get-Content scripts/client/windows/connect-version.txt -Raw).Trim()
Write-Host "VER=$ver"
$checks = @(
  @{f='scripts/client/git-mode.ps1'; p='\[int\]\$TunnelPid'},
  @{f='scripts/client/git-mode.ps1'; p='\[int\]\$Pid\s*='},
  @{f='scripts/client/git-mode.ps1'; p='\$StopEditor'},
  @{f='scripts/client/connect-ui.ps1'; p='AllowEmptyString'},
  @{f='scripts/client/connect-ui.ps1'; p='Get-WindowsSystemProxy'},
  @{f='scripts/client/connect-ui.ps1'; p='LastSessionStatusKey = \$statusKey\s*\r?\n\s*Write-Host \$line'},
  @{f='scripts/client/windows/connect.ps1'; p='Apply-ConnectProxyEnvironment'},
  @{f='scripts/client/windows/connect.ps1'; p="ConnectVersion = '20260720.11'"},
  @{f='scripts/client/windows/connect.ps1'; p='-TunnelPid \$bgPid'}
)
foreach ($c in $checks) {
  $t = Get-Content $c.f -Raw
  $ok = $t -match $c.p
  # negative check for Pid
  if ($c.p -eq '\[int\]\$Pid\s*=') { $ok = -not ($t -match $c.p) }
  Write-Host ("{0} {1} :: {2}" -f ($(if($ok){'PASS'}else{'FAIL'}), $c.f, $c.p))
}
foreach ($rel in @('scripts/client/connect-ui.ps1','scripts/client/git-mode.ps1','scripts/client/windows/connect.ps1')) {
  $tok=$null;$err=$null
  $null=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $rel),[ref]$tok,[ref]$err)
  if ($err -and $err.Count) { Write-Host "PARSE FAIL $rel"; $err | %% { $_ }; exit 1 } else { Write-Host "PARSE OK $rel" }
}
