$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo
$bad = 0
foreach ($f in @('publish\Get-DeployCredentials.ps1','publish\deploy-client-bundles.ps1','publish\finish-sepidz-deploy.ps1','publish\finish-smart-deploy.ps1','publish\deploy-smart-bundle.ps1')) {
  $t = [IO.File]::ReadAllText((Join-Path $repo $f))
  if ($t -match 'sepidz@Admin') { Write-Host "BAD $f sepidz@Admin"; $bad++ }
  elseif ($t -match "(?m)\$SepidzSudoPassword\s*=\s*'(?!YOUR_)[^']+'") { Write-Host "BAD $f real SepidzSudoPassword assign"; $bad++ }
  elseif ($t -match "(?m)\$SmartSudoPassword\s*=\s*'(?!YOUR_)[^']+'") { Write-Host "BAD $f real SmartSudoPassword assign"; $bad++ }
  else { Write-Host "OK $f" }
}
# Examples must be placeholders only
foreach ($f in @('publish\sepidz-deploy.local.ps1.example','publish\smart-deploy.local.ps1.example')) {
  $t = [IO.File]::ReadAllText((Join-Path $repo $f))
  if ($t -match 'sepidz@Admin') { Write-Host "BAD $f"; $bad++ }
  elseif ($t -notmatch 'YOUR_') { Write-Host "WARN $f missing YOUR_ placeholder" }
  else { Write-Host "OK $f placeholders" }
}
$gi = Get-Content (Join-Path $repo '.gitignore') -Raw
if ($gi -match '\*-deploy\.local\.ps1') { Write-Host 'OK gitignore has *-deploy.local.ps1' } else { Write-Host 'BAD gitignore'; $bad++ }
Write-Host "CREDS_BAD=$bad"
exit $bad
