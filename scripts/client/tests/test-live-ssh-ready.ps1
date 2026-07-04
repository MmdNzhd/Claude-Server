# Live smoke test: dot-source connect helpers and run Test-LaptopSshReady
$ErrorActionPreference = 'Stop'
$scriptDir = 'C:\Users\Smart\Desktop\Claude-Connect'
. (Join-Path $scriptDir 'editor-launch.ps1')
. (Join-Path $scriptDir 'git-mode.ps1')
. (Join-Path $scriptDir 'cursor-auth-laptop.ps1')
. (Join-Path $scriptDir 'connect-ui.ps1')

# Minimal stubs connect.ps1 defines before Test-LaptopSshReady
$CfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
$SshDir = Join-Path $env:USERPROFILE '.ssh'
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Extract functions from connect.ps1 without running main script
$src = Get-Content (Join-Path $scriptDir 'connect.ps1') -Raw
$fnBlock = [regex]::Match($src, '(?ms)function Test-AuthorizedKeyFragment.*?^function Ensure-LaptopSshReady').Value
if (-not $fnBlock) { throw 'Could not extract Test-AuthorizedKeyFragment block' }
Invoke-Expression ($fnBlock -replace 'function Ensure-LaptopSshReady.*', '')

Write-Host '=== Live Test-LaptopSshReady ===' -ForegroundColor Cyan

# Fetch real server key fragment (same as connect after bootstrap)
$alias = 'claude-server'
$pubLine = (ssh -n -o BatchMode=yes -o ConnectTimeout=10 $alias 'cat ~/.ssh/claude_laptop.pub 2>/dev/null').Trim()
if (-not $pubLine) { throw 'Could not fetch claude_laptop.pub from server' }
$frag = ($pubLine -split '\s+')[1]
Write-Host "  Server key fragment: $($frag.Substring(0, [Math]::Min(20, $frag.Length)))..." -ForegroundColor DarkGray

# Old broken pattern must throw or mis-bind
$oldOk = $true
try {
    $userAk = Join-Path $SshDir 'authorized_keys'
    $null = Select-String -Path $userAk -Pattern [regex]::Escape($frag) -Quiet -ErrorAction Stop
} catch {
    $oldOk = $false
    Write-Host '  OLD Pattern: FAIL (expected - PS 5.1 binding bug)' -ForegroundColor Yellow
    Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray
}
if ($oldOk) { Write-Host '  OLD Pattern: unexpectedly OK' -ForegroundColor DarkYellow }

# New helper
$userHit = Test-AuthorizedKeyFragment -Path (Join-Path $SshDir 'authorized_keys') -PubFragment $frag
$adminHit = Test-AuthorizedKeyFragment -Path (Join-Path $env:ProgramData 'ssh\administrators_authorized_keys') -PubFragment $frag
Write-Host "  NEW user authorized_keys:  $(if ($userHit) { 'FOUND' } else { 'not found' })" -ForegroundColor $(if ($userHit) { 'Green' } else { 'DarkGray' })
Write-Host "  NEW admin authorized_keys: $(if ($adminHit) { 'FOUND' } else { 'not found' })" -ForegroundColor $(if ($adminHit) { 'Green' } else { 'DarkGray' })

$result = Test-LaptopSshReady -PubFragment $frag
Write-Host "  Test-LaptopSshReady.Ready: $($result.Ready)" -ForegroundColor $(if ($result.Ready) { 'Green' } else { 'Yellow' })
if ($result.Reasons.Count -gt 0) {
    foreach ($r in $result.Reasons) { Write-Host "    - $r" -ForegroundColor DarkYellow }
}

$sshd = Get-Service sshd -ErrorAction SilentlyContinue
Write-Host "  sshd: $($sshd.Status)" -ForegroundColor DarkGray

if ($result.Ready) {
    Write-Host ''
    Write-Host 'PASS live smoke test - should reach project menu without admin prompt' -ForegroundColor Green
    exit 0
}
Write-Host ''
Write-Host 'WARN live smoke test - not Ready (see reasons above)' -ForegroundColor Yellow
exit 0
