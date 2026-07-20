Write-Output '=== ssh agent / keys ==='
ssh-add -l 2>&1 | ForEach-Object { $_ }
Write-Output '=== try IdentityFile only ==='
$opts=@('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-i',"$env:USERPROFILE\.ssh\id_ed25519")
& ssh @opts sepidz@192.168.250.70 'echo ok; hostname' 2>&1 | ForEach-Object { $_ }
Write-Output "exit=$LASTEXITCODE"
Write-Output '=== try id_rsa ==='
if(Test-Path "$env:USERPROFILE\.ssh\id_rsa"){
  & ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -o IdentityAgent=none -i "$env:USERPROFILE\.ssh\id_rsa" sepidz@192.168.250.70 'echo ok' 2>&1 | ForEach-Object { $_ }
  Write-Output "rsa_exit=$LASTEXITCODE"
}
Write-Output '=== config Host for sepidz/250.70 ==='
if(Test-Path "$env:USERPROFILE\.ssh\config"){
  Select-String -Path "$env:USERPROFILE\.ssh\config" -Pattern '250.70|sepidz|cloud' -Context 0,6 | ForEach-Object { $_.ToString() }
}
Write-Output '=== local deploy file keys (names only) ==='
$f='D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1'
if(Test-Path $f){ Select-String -Path $f -Pattern '^\s*\$' | ForEach-Object { ($_.Line -replace '=.*','').Trim() } } else { 'missing local' }
