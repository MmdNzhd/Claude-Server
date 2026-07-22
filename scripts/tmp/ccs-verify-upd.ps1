$ErrorActionPreference='Continue'
# verify server bundle
ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt; ls /usr/local/share/claude-client/cursor-proxy-sidecar.ps1; grep -E 'sidecar|connect-update' /usr/local/share/claude-client/manifest.txt; grep -c UpdateEndpointTarget /usr/local/share/claude-client/connect-update.ps1 || echo bugcount0"
# sync Desktop from publish
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
foreach ($n in @('connect.bat','connect-update.ps1','cursor-proxy-sidecar.ps1','connect.ps1','connect-version.txt','git-mode.ps1','editor-launch.ps1','connect-ui.ps1')) {
  Copy-Item -Force (Join-Path $pub $n) (Join-Path $desk $n) -ErrorAction SilentlyContinue
}
# also sync old 20260717
$old = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'
foreach ($n in @('connect.bat','connect-update.ps1','cursor-proxy-sidecar.ps1','connect.ps1','connect-version.txt','git-mode.ps1','editor-launch.ps1','connect-ui.ps1')) {
  Copy-Item -Force (Join-Path $pub $n) (Join-Path $old $n) -ErrorAction SilentlyContinue
}
Write-Host 'desk_sidecar=' (Test-Path (Join-Path $desk 'cursor-proxy-sidecar.ps1'))
Write-Host 'old_sidecar=' (Test-Path (Join-Path $old 'cursor-proxy-sidecar.ps1'))
Write-Host 'desk_heal=' ((Get-Content (Join-Path $desk 'connect.bat') -Raw) -match 'HEAL_UPDATE_BOOTSTRAP')
# smoke update from old folder
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $old 'connect-update.ps1') -ScriptDir $old -Quiet
Write-Host "old_folder_update_exit=$LASTEXITCODE"
