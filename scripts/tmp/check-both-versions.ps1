$ErrorActionPreference='Continue'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')

function Probe([string]$Label, [string]$Target) {
  Write-Host "==== $Label ($Target) ===="
  $cmds = @(
    "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null; echo",
    "ls -la /usr/local/share/claude-client/connect-version.txt 2>/dev/null",
    "ls -lt /usr/local/share/claude-client 2>/dev/null | head -15",
    "stat -c '%y %n' /usr/local/share/claude-client/connect-version.txt 2>/dev/null"
  )
  foreach ($c in $cmds) {
    $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none -o IdentitiesOnly=yes -i "$env:USERPROFILE\.ssh\id_ed25519" $Target $c 2>&1
    Write-Host ("--- $c ---")
    Write-Host (($out | Out-String).Trim())
    Write-Host ("exit=$LASTEXITCODE")
  }
}

# Try common targets
$targets = @(
  @{ L='Sepidz-sepidz'; T=(Get-SepidzServerTarget) },
  @{ L='Sepidz-smart'; T='smart@192.168.250.70' },
  @{ L='Smart-server'; T='smart@192.168.210.240' }
)
# Also from env/local if Smart target exists
if (Test-Path publish/smart-deploy.local.ps1) {
  $raw = Get-Content publish/smart-deploy.local.ps1 -Raw
  if ($raw -match "SmartSshUser\s*=\s*'([^']+)'") { $su=$Matches[1] } else { $su='smart' }
  if ($raw -match "SmartServerIp\s*=\s*'([^']+)'") { $sip=$Matches[1] } else { $sip='192.168.210.240' }
  $targets += @{ L='Smart-localcfg'; T="$su@$sip" }
}

foreach ($t in $targets) {
  Probe -Label $t.L -Target $t.T
}

Write-Host '==== local package versions ===='
Get-Content scripts/client/windows/connect-version.txt
Get-ChildItem "$env:USERPROFILE\Desktop\claude-publish" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 6 Name,LastWriteTime
