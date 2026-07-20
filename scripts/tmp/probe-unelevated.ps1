$ErrorActionPreference = 'Continue'
$out = Join-Path $env:TEMP 'ak-probe-out.txt'
$adminAk = 'C:\ProgramData\ssh\administrators_authorized_keys'
$frag = 'AAAAC3NzaC1lZDI1NTE5AAAAINmE2C08xhilQRior6V9PApnwNh/WL2VYqa7Lk9+8Gpc'
$wi = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($wi)
$lines = @()
$lines += "IsAdminToken=$($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
$lines += "User=$($wi.Name)"
try {
  $null = Get-Content -LiteralPath $adminAk -ErrorAction Stop
  $lines += 'Get-Content=OK'
} catch { $lines += "Get-Content=FAIL:$($_.Exception.Message)" }
$r = $false
if (Test-Path $adminAk) {
  $r = [bool](Select-String -Path $adminAk -Pattern ([regex]::Escape($frag)) -Quiet -ErrorAction SilentlyContinue)
}
$lines += "FragmentHitSilently=$r"
$lines | Set-Content $out -Encoding UTF8

# Also create task to run this unelevated
$ps1 = Join-Path $env:TEMP 'ak-probe-unelev.ps1'
@'
$out = Join-Path $env:TEMP "ak-probe-out.txt"
$adminAk = "C:\ProgramData\ssh\administrators_authorized_keys"
$frag = "AAAAC3NzaC1lZDI1NTE5AAAAINmE2C08xhilQRior6V9PApnwNh/WL2VYqa7Lk9+8Gpc"
$wi = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($wi)
$lines = @()
$lines += "IsAdminToken=$($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
$lines += "User=$($wi.Name)"
try { $null = Get-Content -LiteralPath $adminAk -ErrorAction Stop; $lines += "Get-Content=OK" } catch { $lines += "Get-Content=FAIL:$($_.Exception.Message)" }
$r = $false
if (Test-Path $adminAk) { $r = [bool](Select-String -Path $adminAk -Pattern ([regex]::Escape($frag)) -Quiet -ErrorAction SilentlyContinue) }
$lines += "FragmentHitSilently=$r"
$lines | Set-Content $out -Encoding UTF8
'@ | Set-Content $ps1 -Encoding UTF8

$task = 'ClaudeAkProbe'
$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ps1`""
cmd /c "schtasks /Delete /F /TN $task" 2>$null | Out-Null
cmd /c "schtasks /Create /F /TN $task /TR `"$tr`" /SC ONCE /ST 23:59 /RU Smart /RL LIMITED /IT" | Out-Null
cmd /c "schtasks /Run /TN $task" | Out-Null
Start-Sleep 5
Write-Host '=== probe out ==='
Get-Content $out -ErrorAction SilentlyContinue
