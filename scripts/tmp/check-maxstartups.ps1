$ErrorActionPreference='Continue'
Write-Output '==== Windows sshd MaxStartups ===='
$cfg = @(
  'C:\ProgramData\ssh\sshd_config',
  "$env:ProgramData\ssh\sshd_config"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
Write-Output "cfg=$cfg"
if ($cfg) {
  Select-String -Path $cfg -Pattern 'MaxStartups|MaxSessions|LoginGraceTime|MaxAuthTries' |
    ForEach-Object { $_.Line }
}
Write-Output ''
Write-Output '==== Default if unset: OpenSSH MaxStartups 10:30:100 ===='
Write-Output '==== connect.ps1 session loop Test-TunnelUp call sites density ===='
$c = Get-Content 'scripts/client/windows/connect.ps1'
for ($i=1445; $i -le 1500; $i++) { '{0}: {1}' -f $i, $c[$i-1] }
Write-Output ''
Write-Output '==== Get-TunnelBanner exact command ===='
$g = Get-Content 'scripts/client/git-mode.ps1'
for ($i=162; $i -le 180; $i++) { '{0}: {1}' -f $i, $g[$i-1] }
Write-Output ''
Write-Output '==== Does diagnostic ignore local_port_open? ===='
$d = Get-Content 'scripts/client/connect-diagnostic.ps1'
for ($i=42; $i -le 55; $i++) { '{0}: {1}' -f $i, $d[$i-1] }
for ($i=210; $i -le 245; $i++) { '{0}: {1}' -f $i, $d[$i-1] }
