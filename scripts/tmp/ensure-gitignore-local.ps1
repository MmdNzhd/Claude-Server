$gi='D:\Smart\Claude-Code-Server\.gitignore'
$raw=Get-Content $gi -Raw -ErrorAction SilentlyContinue
if (-not $raw) { $raw='' }
$need=@('publish/smart-deploy.local.ps1','publish/sepidz-deploy.local.ps1','publish/*-deploy.local.ps1')
$changed=$false
foreach($n in $need){
  if($raw -notmatch [regex]::Escape($n)){ $raw += "`n$n"; $changed=$true }
}
if($changed){ Set-Content -Path $gi -Value $raw.TrimEnd()+"`n" -NoNewline:$false -Encoding utf8; Write-Output 'gitignore_updated' }
else { Write-Output 'gitignore_ok' }
# confirm not tracked
Push-Location 'D:\Smart\Claude-Code-Server'
git check-ignore -v publish/smart-deploy.local.ps1 2>$null
git status --short publish/smart-deploy.local.ps1 publish/sepidz-deploy.local.ps1 2>$null
Pop-Location
Write-Output ("smart_live={0}" -f (python -c "import paramiko,pathlib;c=paramiko.SSHClient();c.set_missing_host_key_policy(paramiko.AutoAddPolicy());c.connect('192.168.210.240',username='smart',key_filename=str(pathlib.Path.home()/'.ssh'/'id_ed25519'),timeout=15,allow_agent=False,look_for_keys=False);_,o,_=c.exec_command('tr -d \"\\r\\n\" < /usr/local/share/claude-client/connect-version.txt');print(o.read().decode().strip());c.close()"))
