$ErrorActionPreference = 'Stop'
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'
$targets = @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows')
)
$files = @(
  'connect.bat','connect-boot.ps1','connect-version.txt','connect-update.ps1','connect.ps1',
  'connect-ui.ps1','git-mode.ps1','editor-launch.ps1','cursor-auth-laptop.ps1','connect-diagnostic.ps1'
)
foreach ($t in $targets) {
  New-Item -ItemType Directory -Force -Path $t | Out-Null
  foreach ($f in $files) {
    Copy-Item (Join-Path $pub $f) (Join-Path $t $f) -Force
  }
  $v = (Get-Content (Join-Path $t 'connect-version.txt') -Raw).Trim()
  $elevOk = [int]((Get-Content (Join-Path $t 'connect.ps1') -Raw) -match 'Do NOT -Wait')
  $foreignOk = [int]((Get-Content (Join-Path $t 'git-mode.ps1') -Raw) -match 'Get-ForeignTunnelPortSet')
  Write-Host "SYNC $t ver=$v elev=$elevOk foreign=$foreignOk"
}
# share version
Write-Host "SHARE=$(Get-Content /usr/local/share/claude-client/connect-version.txt -ErrorAction SilentlyContinue)"

# Kill ONLY unelevated waiter parents (PPID of elevated), not elevated session if user still using it
# Actually user wants CMD closed - kill unelevated connect-boot that has elevated child
$boots = Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object { $_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -match 'connect-boot\.ps1' -and $_.CommandLine -notmatch 'Cursor|ClaudeServerCursor' }
foreach ($b in $boots) {
  $kids = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.ParentProcessId -eq $b.ProcessId -and $_.CommandLine -match 'connect-boot\.ps1' })
  $isElevChild = $false
  # If this process has a connect-boot child, it is the waiter parent -> kill parent only
  if ($kids.Count -gt 0) {
    Write-Host "KILL_WAITER_PARENT pid=$($b.ProcessId) child=$($kids[0].ProcessId)"
    Stop-Process -Id $b.ProcessId -Force -EA SilentlyContinue
  }
}
Write-Host 'SYNC_DONE'
