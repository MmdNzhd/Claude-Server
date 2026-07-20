$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$creds = Get-DeployCredentials -Target Sepidz -ErrorAction SilentlyContinue
if(-not $creds){ $creds = Get-SepidzDeployCredentials -ErrorAction SilentlyContinue }
Write-Output ("creds type=" + $(if($creds){$creds.GetType().Name}else{'null'}))
if($creds){
  Write-Output ("user=" + $creds.UserName)
  Write-Output ("hasPass=" + [bool]$creds.Password)
}
# Test SSH with password via plink/sshpass style
$pub = Get-ChildItem "$env:USERPROFILE\Desktop\claude-publish" -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1
Write-Output ("package=" + $pub.FullName)
# Try ssh with BatchMode first
ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes sepidz@192.168.250.70 "echo ssh_ok; cat /opt/claude-code-client/windows/connect-version.txt 2>/dev/null; ls /usr/local/share/claude-code-client/windows/connect-version.txt 2>/dev/null; find /usr/local -name connect-version.txt 2>/dev/null | head -5" 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "exit=$LASTEXITCODE"
