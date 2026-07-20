$ErrorActionPreference = 'Continue'
$adminAk = 'C:\ProgramData\ssh\administrators_authorized_keys'
Write-Host '=== admin keys content (redacted prefix) ==='
Get-Content $adminAk -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_ -match 'ssh-ed25519\s+(\S+)') { 'KEY frag=' + $Matches[1].Substring(0,[Math]::Min(20,$Matches[1].Length)) + '... full_len=' + $_.Length }
  else { $_ }
}

# Server laptop pub from last connect log line
$wantFrag = 'AAAAC3NzaC1lZDI1NTE5AAAAINmE2C08xhilQRior6V9PApnwNh/WL2VYqa7Lk9+8Gpc'
$hit = Select-String -Path $adminAk -Pattern ([regex]::Escape($wantFrag)) -Quiet -ErrorAction SilentlyContinue
Write-Host "server_key_in_admin_ak=$hit"

# Fetch live pub from server
$pub = (& ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 "cat ~/.ssh/claude_laptop.pub" 2>$null)
Write-Host "server_pub=$pub"
if (-not $pub) { Write-Host 'FAIL fetch pub'; exit 1 }

# Write pending + run AdminFix elevated via schtasks
$cfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$pending = Join-Path $cfgDir 'adminfix.pending'
@(
  "PUB=$pub",
  "LAPTOP_USER=Smart",
  "FIREWALL=1",
  "FORCE_RESTART=1"
) | Set-Content -Path $pending -Encoding ASCII

$connectPs1 = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.ps1'
$task = 'ClaudeConnectAdminFixOnce'
$tr = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File `"$connectPs1`" -AdminFix"
cmd /c "schtasks /Delete /F /TN $task" 2>$null | Out-Null
# Highest privileges for writing ProgramData\ssh
$create = cmd /c "schtasks /Create /F /TN $task /TR `"$tr`" /SC ONCE /ST 23:59 /RU Smart /RL HIGHEST /IT"
Write-Host "CREATE=$create EC=$LASTEXITCODE"
$run = cmd /c "schtasks /Run /TN $task"
Write-Host "RUN=$run EC=$LASTEXITCODE"
Start-Sleep -Seconds 8
$hit2 = Select-String -Path $adminAk -Pattern ([regex]::Escape($wantFrag)) -Quiet -ErrorAction SilentlyContinue
Write-Host "server_key_in_admin_ak_after=$hit2"
Write-Host "pending_exists=$(Test-Path $pending)"
cmd /c "schtasks /Query /TN $task /V /FO LIST" | Select-String 'Status|Last Run|Last Result'
