$el = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$c = Get-Content $el
$start = ($c | Select-String -Pattern 'function Stop-CursorServerProfileTreeIfNeeded' | Select-Object -First 1).LineNumber
for ($i=$start-1; $i -lt ($start+40); $i++) { '{0,4}|{1}' -f ($i+1), $c[$i] }
Write-Host '==== parse editor-launch ===='
$null = [System.Management.Automation.Language.Parser]::ParseFile($el, [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { $_.ToString() }; exit 1 } else { 'PARSE_OK' }
$conn = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$null = [System.Management.Automation.Language.Parser]::ParseFile($conn, [ref]$null, [ref]$errs2)
if ($errs2) { $errs2 | ForEach-Object { $_.ToString() }; exit 1 } else { 'CONNECT_PARSE_OK' }
Select-String -Path $conn -Pattern 'skip_auth_relaunch|ConnectVersion' | Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }
# Sync to Desktop paths user actually runs
$srcRoot = 'D:\Smart\Claude-Code-Server\scripts\client'
$targets = @(
  'C:\Users\Smart\Desktop\Claude-Connect',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
)
$files = @('windows\connect.ps1','windows\connect-version.txt','editor-launch.ps1','git-mode.ps1','connect-ui.ps1','windows\connect.bat','windows\connect-update.ps1','windows\connect-boot.ps1')
foreach ($t in $targets) {
  if (-not (Test-Path $t)) { Write-Host "MISSING $t"; continue }
  Write-Host "SYNC -> $t"
  foreach ($f in $files) {
    $src = Join-Path $srcRoot $f
    # map: for Claude-Connect flat layout vs windows subdir
    if ($t -like '*\windows') {
      $leaf = Split-Path $f -Leaf
      $dst = Join-Path $t $leaf
      # also editor-launch lives next to connect in windows folder for publish zip
      if ($f -like 'windows\*') { $dst = Join-Path $t (Split-Path $f -Leaf) }
      else { $dst = Join-Path $t (Split-Path $f -Leaf) }
    } else {
      # Claude-Connect: typically flat with connect.ps1 at root
      $leaf = Split-Path $f -Leaf
      $dst = Join-Path $t $leaf
      if (-not (Test-Path (Split-Path $dst -Parent))) { continue }
    }
    if (Test-Path $src) {
      Copy-Item -Force $src $dst -ErrorAction SilentlyContinue
      if (Test-Path $dst) { Write-Host "  OK $leaf" } else { Write-Host "  FAIL $leaf -> $dst" }
    }
  }
}
# Show versions on live paths
foreach ($p in @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt',
  'C:\Users\Smart\Desktop\Claude-Connect\connect-version.txt',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt'
)) {
  if (Test-Path $p) { Write-Host "VER $p = $((Get-Content $p -Raw).Trim())" }
}
