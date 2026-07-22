#Requires -Version 5.1
# Run remote sudo on Sepidz from the laptop.
# Smart server cannot route to 192.168.250.70; SSH sessions on Sepidz often hang on exit — kill after __DONE__.
# Password from publish/sepidz-deploy.local.ps1 only.
# Usage: powershell -File sepidz-sudo-via-laptop.ps1 -- <bash command...>
$ErrorActionPreference = 'Stop'
$argsList = @($args)
if ($argsList.Count -ge 1 -and $argsList[0] -eq '--') {
  if ($argsList.Count -eq 1) { throw 'usage: sepidz-sudo-via-laptop.ps1 -- <command...>' }
  $argsList = $argsList[1..($argsList.Count - 1)]
}
if ($argsList.Count -lt 1) { throw 'usage: sepidz-sudo-via-laptop.ps1 -- <command...>' }
$remoteCmd = ($argsList -join ' ')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $repoRoot 'publish\sepidz-deploy.local.ps1'))) {
  $repoRoot = (Get-Location).Path
}
$dep = Join-Path $repoRoot 'publish\sepidz-deploy.local.ps1'
$raw = Get-Content -LiteralPath $dep -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$sshUser = 'sepidz'
$serverIp = '192.168.250.70'
$mu = [regex]::Match($raw, '(?m)^\s*\$SepidzSshUser\s*=\s*''([^'']*)''')
$mh = [regex]::Match($raw, '(?m)^\s*\$SepidzServerIp\s*=\s*''([^'']*)''')
if ($mu.Success) { $sshUser = $mu.Groups[1].Value }
if ($mh.Success) { $serverIp = $mh.Groups[1].Value }
if ([string]::IsNullOrWhiteSpace($pw)) { throw 'empty SepidzSudoPassword' }
$target = "$sshUser@$serverIp"

$localSh = Join-Path $env:TEMP ('sepidz-sudo-' + [guid]::NewGuid().ToString('n') + '.sh')
$remoteSh = '/tmp/sepidz-sudo-run.sh'
try {
  $body = "#!/bin/bash`nset -euo pipefail`n$remoteCmd`necho __DONE__`n"
  [IO.File]::WriteAllText($localSh, $body.Replace("`r`n", "`n").Replace("`r", "`n"), (New-Object Text.UTF8Encoding $false))
  $scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=30','-o','ControlMaster=no','-o','ControlPath=none','-q', $localSh, (${target} + ':' + $remoteSh))
  & scp @scpArgs
  if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'ssh.exe'
  $psi.Arguments = "-n -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -o ControlPath=none $target `"printf '%s\n' '$pw' | sudo -S -p '' bash $remoteSh`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $out = New-Object System.Text.StringBuilder
  $deadline = [datetime]::UtcNow.AddSeconds(90)
  while ([datetime]::UtcNow -lt $deadline) {
    if (-not $p.HasExited) {
      while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        if ($null -eq $line) { break }
        [void]$out.AppendLine($line)
        [Console]::Out.WriteLine($line)
        if ($line -match '__DONE__') {
          Start-Sleep -Milliseconds 200
          try { $p.Kill() } catch {}
          break
        }
      }
    }
    if ($p.HasExited) { break }
    if ($out.ToString() -match '__DONE__') { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $p.HasExited) { try { $p.Kill() } catch {} }
  $err = $p.StandardError.ReadToEnd()
  if ($err) {
    foreach ($line in ($err -split "`n")) {
      if ($line -and ($line -notmatch '(?i)password')) { [Console]::Error.WriteLine($line) }
    }
  }
  if ($out.ToString() -notmatch '__DONE__') { exit 1 }
  exit 0
} finally {
  Remove-Item -Force -LiteralPath $localSh -ErrorAction SilentlyContinue
}
