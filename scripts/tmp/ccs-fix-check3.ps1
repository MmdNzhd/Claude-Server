$ErrorActionPreference = 'Continue'
Write-Host '=== settings proxy ==='
$s = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
if (Test-Path $s) {
  Get-Content $s -Raw | Select-String -Pattern 'proxy|disableHttp2' -AllMatches | ForEach-Object { $_.Line.Substring(0, [Math]::Min(500, $_.Line.Length)) }
} else { Write-Host 'no settings' }

Write-Host '=== brace balance connect.ps1 skip_remount region ==='
$c = Get-Content 'scripts\client\windows\connect.ps1' -Raw
$i = $c.IndexOf('skipRemount')
Write-Host $c.Substring([Math]::Max(0,$i-100), [Math]::Min(1200, $c.Length - [Math]::Max(0,$i-100)))

Write-Host '=== Get-Mounts Healthy cost ==='
. .\scripts\client\git-mode.ps1
# simulate without live CM - just check function body
$gm = Get-Content 'scripts\client\windows\connect.ps1' -Raw
if ($gm -match 'Test-ProjectMountHealthy -ProjectId \$id') { Write-Host 'WARN Get-Mounts calls Healthy per project (slow)' }

Write-Host '=== owner path ==='
. .\scripts\client\git-mode.ps1
$path = Get-CursorProxyOwnerPath
Write-Host "ownerPath=$path"
Write-Host ("exists={0}" -f (Test-Path $path))

Write-Host '=== Desktop connect parse ==='
$errs=$null;$tok=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect.ps1'), [ref]$tok, [ref]$errs)
if ($errs) { $errs | % { $_.ToString() } } else { 'PARSE_OK desktop connect' }

Write-Host '=== try Update policy helpers parse ==='
$u = Get-Content 'scripts\client\windows\connect-update.ps1' -Raw
if ($u -match 'UPDATE_OPTIONAL_SKIP') { 'optional gate present' }
# Check for broken string from gate insert
if ($u -match '\$manifestRaw = Invoke-SshCat' ) { 'manifest ok' }
