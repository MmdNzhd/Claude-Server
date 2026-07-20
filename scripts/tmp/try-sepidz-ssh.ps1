$ErrorActionPreference='Continue'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')
Write-Host ("SepidzTarget={0}" -f (Get-SepidzServerTarget))
Write-Host ("HasSudoPw={0}" -f [bool](Get-SepidzSudoPassword))

foreach ($t in @((Get-SepidzServerTarget), 'smart@192.168.250.70', 'sepidz@192.168.250.70')) {
  Write-Host ">>> ssh $t"
  $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -o PreferredAuthentications=publickey $t 'echo OK; whoami; hostname' 2>&1
  Write-Host (" exit={0} {1}" -f $LASTEXITCODE, (($out | Out-String) -replace '\s+',' ').Trim().Substring(0,[Math]::Min(200,(($out|Out-String)-replace '\s+',' ').Trim().Length)))
}

# Try with ssh-agent keys listed
Write-Host '=== ssh-add -l ==='
ssh-add -l 2>&1
