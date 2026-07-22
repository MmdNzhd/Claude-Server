$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

# Run hard multi-agent test
& (Join-Path $root 'scripts\client\tests\test-hard-multi-agent-regressions.ps1')
if ($LASTEXITCODE -ne 0) { throw "hard tests failed $LASTEXITCODE" }

& (Join-Path $root 'publish\publish.ps1') -SmartOnly -SkipVersionBump
Write-Host "PUB=$LASTEXITCODE"

# sync both desktop trees
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
  foreach ($f in $files) {
    $src = Join-Path $pub $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $t $f) -Force }
  }
  $v = (Get-Content (Join-Path $t 'connect-version.txt') -Raw).Trim()
  $multi = [int]((Get-Content (Join-Path $t 'connect-boot.ps1') -Raw) -match 'ClaudeConnect#')
  Write-Host "SYNC $t ver=$v multi=$multi"
}

# free any leftover connect boots so user can launch
Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object {
    $_.CommandLine -and $_.CommandLine -match 'connect-boot\.ps1' -and
    $_.CommandLine -notmatch 'Cursor|ClaudeServerCursor|patch-|diag-|sync-|pub|parse'
  } |
  ForEach-Object { Write-Host "KILL $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }

Write-Host 'ALL_DONE'
