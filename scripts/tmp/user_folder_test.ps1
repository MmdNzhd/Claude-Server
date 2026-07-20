$ErrorActionPreference = 'Stop'
$folder = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Write-Host "FOLDER=$folder"
if (-not (Test-Path $folder)) { throw "folder missing: $folder" }

$verBefore = (Get-Content (Join-Path $folder 'connect-version.txt') -Raw).Trim()
$ipBefore = [regex]::Match((Get-Content (Join-Path $folder 'connect.ps1') -Raw), '192\.168\.\d+\.\d+').Value
$aliasBefore = [regex]::Match((Get-Content (Join-Path $folder 'connect.ps1') -Raw), '\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
Write-Host "BEFORE ver=$verBefore ip=$ipBefore alias=$aliasBefore"

# Force an update path: set local version older, then run connect-update like connect.bat does
$backup = Join-Path $env:TEMP 'user-folder-ver-backup.txt'
Copy-Item (Join-Path $folder 'connect-version.txt') $backup -Force
Set-Content (Join-Path $folder 'connect-version.txt') '20260717.8'

$upd = Join-Path $folder 'connect-update.ps1'
$log = Join-Path $env:TEMP 'user-folder-update.log'
$err = Join-Path $env:TEMP 'user-folder-update.err'
$p = Start-Process powershell -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',$upd,'-ScriptDir',$folder
) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err

if (-not $p.WaitForExit(120000)) {
  try { $p.Kill() } catch {}
  Write-Host 'RESULT=FAIL reason=timeout'
  Write-Host (Get-Content $log -Raw -ErrorAction SilentlyContinue)
  exit 2
}

Write-Host '--- update output ---'
Write-Host ((Get-Content $log -Raw -ErrorAction SilentlyContinue) + '')
if (Test-Path $err) {
  $e = (Get-Content $err -Raw -ErrorAction SilentlyContinue) + ''
  if ($e.Trim()) { Write-Host '--- stderr ---'; Write-Host $e }
}

$verAfter = (Get-Content (Join-Path $folder 'connect-version.txt') -Raw).Trim()
$ipAfter = [regex]::Match((Get-Content (Join-Path $folder 'connect.ps1') -Raw), '192\.168\.\d+\.\d+').Value
$aliasAfter = [regex]::Match((Get-Content (Join-Path $folder 'connect.ps1') -Raw), '\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
$src = ((Get-Content $log -Raw -ErrorAction SilentlyContinue) + '')
$fromSepidz = $src -match 'sepidz@192\.168\.250\.70'
$fromSmartAlias = $src -match 'Update source:\s*claude-server(\s|$)'
$got22 = ($verAfter -eq '20260717.22')

Write-Host "AFTER ver=$verAfter ip=$ipAfter alias=$aliasAfter exit=$($p.ExitCode)"

$ok = $true
$reasons = @()
if (-not $fromSepidz) { $ok = $false; $reasons += 'update-source-not-sepidz' }
if ($fromSmartAlias) { $ok = $false; $reasons += 'used-claude-server-alias' }
if ($got22) { $ok = $false; $reasons += 'landed-on-smart-22' }
if ($ipAfter -ne '192.168.250.70') { $ok = $false; $reasons += "ip=$ipAfter" }
if ($verAfter -ne '20260717.38') { $ok = $false; $reasons += "ver=$verAfter" }
if ($aliasAfter -ne 'claude-server-sepidz') { $ok = $false; $reasons += "alias=$aliasAfter" }

# live check
function SshOut($t,$c) {
  $o = Join-Path $env:TEMP ('t'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $sp = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  [void]$sp.WaitForExit(15000)
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
}
$live = SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
$smart = SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
Write-Host "LIVE sepidz=$live smart=$smart"
if ($live -ne '20260717.38') { $ok = $false; $reasons += "live=$live" }

if ($ok) {
  Write-Host 'RESULT=PASS'
  exit 0
} else {
  Write-Host ("RESULT=FAIL reasons=" + ($reasons -join ','))
  exit 1
}
