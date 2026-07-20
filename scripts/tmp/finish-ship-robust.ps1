$ErrorActionPreference='Continue'
Write-Host '=== kill hung publish/wait/ssh (keep -R tunnel) ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'run-full-publish|wait-publish|publish\\publish\.ps1|deploy-client-bundles|deploy-smart-bundle') } |
  ForEach-Object {
    Write-Host "  kill ps pid=$($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -and
    ($_.CommandLine -match '192\.168\.210\.240|192\.168\.250\.70|smart@|sepidz@') -and
    ($_.CommandLine -notmatch '-R\s+\d+:localhost:22')
  } |
  ForEach-Object {
    Write-Host "  kill ssh pid=$($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Start-Sleep -Seconds 2

$pack='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717'
$sepid='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717'
Write-Host "smart_pack=$(Test-Path $pack) sepid_pack=$(Test-Path $sepid)"
Write-Host "smart_ver=$((Get-Content (Join-Path $pack 'windows\connect-version.txt') -Raw).Trim())"
if (Test-Path (Join-Path $sepid 'claude-code\windows\connect-version.txt')) {
  Write-Host "sepid_ver=$((Get-Content (Join-Path $sepid 'claude-code\windows\connect-version.txt') -Raw).Trim())"
  Write-Host "sepid_nc=$([bool](Select-String -Path (Join-Path $sepid 'claude-code\windows\git-mode.ps1') -Pattern 'nc -w 2' -Quiet))"
}

# If sepid pack missing or wrong version, rebuild sepid only
$needSepid = $true
if (Test-Path (Join-Path $sepid 'claude-code\windows\connect-version.txt')) {
  $sv = (Get-Content (Join-Path $sepid 'claude-code\windows\connect-version.txt') -Raw).Trim()
  $needSepid = ($sv -ne '20260717.5')
}
if ($needSepid -or -not (Select-String -Path (Join-Path $sepid 'claude-code\windows\git-mode.ps1') -Pattern 'banner_miss_tcp_open' -Quiet -ErrorAction SilentlyContinue)) {
  Write-Host '=== rebuild Sepidz package only ==='
  & powershell -NoProfile -ExecutionPolicy Bypass -File 'publish\publish.ps1' -SkipVersionBump -SkipServerDeploy -SepidzOnly
  if ($LASTEXITCODE -ne 0) { throw "sepid publish failed: $LASTEXITCODE" }
}

Write-Host '=== deploy via deploy-client-bundles (both) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File 'publish\deploy-client-bundles.ps1' `
  -ProjectRoot (Resolve-Path '.').Path `
  -SmartClientRoot $pack `
  -SepidClientRoot (Join-Path $sepid 'claude-code') `
  -DeploySmart:$true `
  -DeploySepidz:$true
Write-Host "DEPLOY_EXIT=$LASTEXITCODE"
