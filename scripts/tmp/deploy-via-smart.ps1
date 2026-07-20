$ErrorActionPreference='Stop'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')

# Quick connectivity matrix with short timeouts
function TrySsh([string]$Target) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=6 -o ConnectionAttempts=1 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 $Target 'echo OK; whoami' 2>&1
  $sw.Stop()
  $s = (($out | Out-String) -replace '\s+',' ').Trim()
  if ($s.Length -gt 180) { $s = $s.Substring(0,180) }
  Write-Host ("{0} ms={1} exit={2} {3}" -f $Target, $sw.ElapsedMilliseconds, $LASTEXITCODE, $s)
  return ($LASTEXITCODE -eq 0)
}

$okSmart = TrySsh 'smart@192.168.250.70'
$okSepidz = $false
try { $okSepidz = TrySsh 'sepidz@192.168.250.70' } catch { Write-Host "sepidz throw $_" }

# List Get-DeployCredentials functions
Get-Command Get-Sepidz* | ForEach-Object { $_.Name }

# Does local file have SSH password?
$raw = Get-Content publish/sepidz-deploy.local.ps1 -Raw
Write-Host 'local keys:'
[regex]::Matches($raw, '\$(\w+)\s*=') | ForEach-Object { $_.Groups[1].Value }

if ($okSmart -and -not $okSepidz) {
  Write-Host 'DEPLOY via smart@ with Sepidz sudo password'
  $OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
  $sepidDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1
  $root = (Resolve-Path '.').Path
  & (Join-Path $root 'publish\deploy-client-bundles.ps1') `
    -ProjectRoot $root `
    -SepidClientRoot (Join-Path $sepidDir.FullName 'claude-code') `
    -SepidServer 'smart@192.168.250.70' `
    -DeploySmart:$false `
    -DeploySepidz:$true
}
