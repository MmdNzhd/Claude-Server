$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

# verify elevate
$c = [IO.File]::ReadAllText("$root\scripts\client\windows\connect.ps1")
if ($c -match 'PassThru -Wait') { throw 'elevate still has PassThru -Wait' }
if ($c -notmatch "ConnectVersion = '20260721\.10'") { throw 'version not .10' }
if ($c -notmatch 'Do NOT -Wait') { throw 'elevate comment missing' }
Write-Host 'OK elevate verified'

# test assert
$tp = "$root\scripts\client\tests\test-connect-pipeline.ps1"
$t = [IO.File]::ReadAllText($tp)
if ($t -notmatch 'elevate does not -Wait') {
  $lines = [IO.File]::ReadAllLines($tp)
  $out = New-Object System.Collections.Generic.List[string]
  $done = $false
  foreach ($ln in $lines) {
    [void]$out.Add($ln)
    if (-not $done -and $ln -match 'self-elevates to administrator') {
      [void]$out.Add("    Assert (`$src -notmatch 'Verb RunAs -ArgumentList `$elevArgs -PassThru -Wait') `"`$rel elevate does not -Wait (avoids stuck unelevated console)`"")
      $done = $true
    }
  }
  if (-not $done) { throw 'test insert failed' }
  [IO.File]::WriteAllLines($tp, $out)
  Write-Host 'OK test assert'
} else { Write-Host 'OK test already' }

# seed foreign ports known from today's log (Amir)
$cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
$lines = @(Get-Content $cfg -ErrorAction SilentlyContinue)
$lines = @($lines | Where-Object { $_ -notmatch '^FOREIGN_TUNNEL_PORTS=' })
$lines += 'FOREIGN_TUNNEL_PORTS=21006,21007,21008'
Set-Content -Path $cfg -Value $lines -Encoding ASCII
Write-Host 'OK seeded FOREIGN_TUNNEL_PORTS'
Get-Content $cfg

# sync version file already done
Write-Host 'FINISH_OK'
