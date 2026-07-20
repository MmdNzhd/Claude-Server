#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = 'D:\Smart\Claude-Code-Server'
$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$SmartRoot = Join-Path $OutBase 'claude-code-client-20260715'
$SepidRoot = Join-Path $OutBase 'claude-code-sepidz-20260715\claude-code'

if (-not (Test-Path $SmartRoot)) { throw "Missing Smart publish: $SmartRoot" }
if (-not (Test-Path $SepidRoot)) { throw "Missing Sepidz publish: $SepidRoot" }

# Sync kill-fix + versions from repo into Desktop packs before deploy
$syncPairs = @(
  @{ Src = 'scripts\client\editor-launch.ps1'; DstSmart = 'windows\editor-launch.ps1'; DstSepid = 'windows\editor-launch.ps1' },
  @{ Src = 'scripts\client\windows\connect.ps1'; DstSmart = 'windows\connect.ps1'; DstSepid = 'windows\connect.ps1' },
  @{ Src = 'scripts\client\windows\connect-version.txt'; DstSmart = 'windows\connect-version.txt'; DstSepid = 'windows\connect-version.txt' },
  @{ Src = 'scripts\client\mac\connect.sh'; DstSmart = 'mac\connect.sh'; DstSepid = 'mac\connect.sh' },
  @{ Src = 'scripts\client\mac\connect-version.txt'; DstSmart = 'mac\connect-version.txt'; DstSepid = 'mac\connect-version.txt' }
)
foreach ($p in $syncPairs) {
  $src = Join-Path $ProjectRoot $p.Src
  if (-not (Test-Path $src)) { throw "Missing repo file: $src" }
  Copy-Item -LiteralPath $src -Destination (Join-Path $SmartRoot $p.DstSmart) -Force
  Copy-Item -LiteralPath $src -Destination (Join-Path $SepidRoot $p.DstSepid) -Force
}

# Keep Sepidz Smart IP patched in windows/mac connect after sync
$sepidIpFiles = @(
  (Join-Path $SepidRoot 'windows\connect.ps1'),
  (Join-Path $SepidRoot 'mac\connect.sh')
)
foreach ($f in $sepidIpFiles) {
  $c = Get-Content $f -Raw
  $n = $c -replace '192\.168\.210\.240', '192.168.250.70'
  if ($n -ne $c) {
    Set-Content -Path $f -Value $n -Encoding UTF8 -NoNewline
    Write-Host "Patched Sepidz IP in $f" -ForegroundColor Cyan
  }
}

Write-Host 'Pre-deploy versions:' -ForegroundColor White
@(
  (Join-Path $SmartRoot 'windows\connect-version.txt'),
  (Join-Path $SmartRoot 'mac\connect-version.txt'),
  (Join-Path $SepidRoot 'windows\connect-version.txt'),
  (Join-Path $SepidRoot 'mac\connect-version.txt')
) | ForEach-Object { Write-Host ("  {0} = {1}" -f $_, ((Get-Content $_ -Raw).Trim())) }

Write-Host ''
Write-Host 'Deploying Smart + Sepidz...' -ForegroundColor White
& (Join-Path $ProjectRoot 'publish\deploy-client-bundles.ps1') `
  -ProjectRoot $ProjectRoot `
  -SmartClientRoot $SmartRoot `
  -SepidClientRoot $SepidRoot `
  -DeploySmart:$true `
  -DeploySepidz:$true `
  -ContinueOnDeployError

Write-Host ''
Write-Host '=== VERIFY ===' -ForegroundColor White
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
function Probe($label,$target) {
  $a = @('-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=accept-new', $target,
    'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL"); echo force=$(grep -c pre_launch_agent_or_new_window "$EL"); echo retry=$(grep -c LAUNCH_RETRY_NO_KILL "$EL")')
  $out = "$env:TEMP\verify-$label.out"; $err = "$env:TEMP\verify-$label.err"
  $p = Start-Process -FilePath ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  [void]$p.WaitForExit(20000)
  Write-Host "--- $label ---"
  if (Test-Path $out) { Get-Content $out | ForEach-Object { Write-Host $_ } }
}
Probe 'SMART' 'smart@192.168.210.240'
Probe 'SEPIDZ' 'sepidz@192.168.250.70'
