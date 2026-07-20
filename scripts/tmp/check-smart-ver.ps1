$ErrorActionPreference='Continue'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')

Write-Host '==== Sepidz (smart@250.70) ===='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.250.70 "hostname; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo; stat -c '%y' /usr/local/share/claude-client/connect-version.txt 2>/dev/null; ls /usr/local/share/claude-client/*.zip 2>/dev/null | tail -5"

Write-Host '==== Smart (210.240) ===='
$smartTargets = @('smart@192.168.210.240')
if (Test-Path publish/smart-deploy.local.ps1) {
  $raw = Get-Content publish/smart-deploy.local.ps1 -Raw
  Write-Host 'smart-local vars:'
  [regex]::Matches($raw, '\$([A-Za-z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value }
}
foreach ($t in $smartTargets) {
  Write-Host "try $t"
  ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none -o IdentitiesOnly=yes -i "$env:USERPROFILE\.ssh\id_ed25519" $t "hostname; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo; stat -c '%y' /usr/local/share/claude-client/connect-version.txt 2>/dev/null" 2>&1 | ForEach-Object { Write-Host $_ }
  Write-Host "exit=$LASTEXITCODE"
}

# Also try with password if Get-SmartSudoPassword works as ssh? Unlikely.
# Check desktop for smart package mtime suggesting deploy happened
Write-Host '==== desktop publish folders ===='
Get-ChildItem "$env:USERPROFILE\Desktop\claude-publish" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,LastWriteTime,Length | Format-Table -AutoSize | Out-String | Write-Host

Write-Host '==== local repo version ===='
Get-Content scripts/client/windows/connect-version.txt
Get-Content scripts/client/mac/connect-version.txt
