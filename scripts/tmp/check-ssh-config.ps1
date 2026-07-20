$ErrorActionPreference='Continue'
$cfg=Join-Path $env:USERPROFILE '.ssh\config'
$i=Get-Item $cfg
Write-Host ("config_bytes=" + $i.Length)
Write-Host ("config_lines=" + (Get-Content $cfg | Measure-Object -Line).Lines)
# First/last hosts
Select-String -Path $cfg -Pattern '^\s*Host\s+' | Select-Object -First 20 | ForEach-Object { "$($_.LineNumber):$($_.Line)" }
Write-Host '--- tail hosts ---'
Select-String -Path $cfg -Pattern '^\s*Host\s+' | Select-Object -Last 10 | ForEach-Object { "$($_.LineNumber):$($_.Line)" }
# Blank line runs
$raw=[IO.File]::ReadAllText($cfg)
$m=[regex]::Matches($raw, "(`r?`n){20,}")
Write-Host ("huge_blank_runs=" + $m.Count)
if ($m.Count -gt 0) {
  Write-Host ("largest_blank_run_chars=" + ($m | Sort-Object Length -Descending | Select-Object -First 1).Length)
}

# Minimal ssh with -F NUL and explicit key
Write-Host '=== direct ssh -F nul ==='
$key=Join-Path $env:USERPROFILE '.ssh\id_ed25519'
if (-not (Test-Path $key)) { $key=Join-Path $env:USERPROFILE '.ssh\claude_laptop' }
Write-Host "key=$key exists=$(Test-Path $key)"
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='ssh'
$psi.Arguments="-F NUL -o BatchMode=yes -o IdentitiesOnly=yes -i `"$key`" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o GSSAPIAuthentication=no sepidz@192.168.250.70 echo PONG"
$psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
$p=[Diagnostics.Process]::Start($psi)
if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT' }
else { Write-Host ("exit=$($p.ExitCode) out=$($p.StandardOutput.ReadToEnd().Trim()) err=$($p.StandardError.ReadToEnd().Trim())") }

Write-Host '=== direct smart ==='
$psi2=New-Object Diagnostics.ProcessStartInfo
$psi2.FileName='ssh'
$psi2.Arguments="-F NUL -o BatchMode=yes -o IdentitiesOnly=yes -i `"$key`" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o GSSAPIAuthentication=no smart@192.168.210.240 echo PONG"
$psi2.UseShellExecute=$false; $psi2.RedirectStandardOutput=$true; $psi2.RedirectStandardError=$true; $psi2.CreateNoWindow=$true
$p2=[Diagnostics.Process]::Start($psi2)
if (-not $p2.WaitForExit(20000)) { try{$p2.Kill()}catch{}; Write-Host 'TIMEOUT' }
else { Write-Host ("exit=$($p2.ExitCode) out=$($p2.StandardOutput.ReadToEnd().Trim()) err=$($p2.StandardError.ReadToEnd().Trim())") }
