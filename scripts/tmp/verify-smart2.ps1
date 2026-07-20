$ErrorActionPreference='Continue'
$sshArgs=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-o','ServerAliveInterval=3','smart@192.168.210.240')
Write-Output '--- version ---'
$p = Start-Process -FilePath ssh -ArgumentList ($sshArgs + @('cat /usr/local/share/claude-client/connect-version.txt')) -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'C:\Users\Smart\AppData\Local\Temp\smart-ver.txt' -RedirectStandardError 'C:\Users\Smart\AppData\Local\Temp\smart-ver.err'
Write-Output ("exit=" + $p.ExitCode)
Write-Output 'stdout:'; Get-Content 'C:\Users\Smart\AppData\Local\Temp\smart-ver.txt' -ErrorAction SilentlyContinue
Write-Output 'stderr:'; Get-Content 'C:\Users\Smart\AppData\Local\Temp\smart-ver.err' -ErrorAction SilentlyContinue
Write-Output '--- ls bundle ---'
$p2 = Start-Process -FilePath ssh -ArgumentList ($sshArgs + @('ls -la /usr/local/share/claude-client/connect-version.txt /usr/local/share/claude-client/windows/connect-version.txt 2>&1 | head -20')) -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'C:\Users\Smart\AppData\Local\Temp\smart-ls.txt' -RedirectStandardError 'C:\Users\Smart\AppData\Local\Temp\smart-ls.err'
Write-Output ("ls_exit=" + $p2.ExitCode)
Get-Content 'C:\Users\Smart\AppData\Local\Temp\smart-ls.txt' -ErrorAction SilentlyContinue
Get-Content 'C:\Users\Smart\AppData\Local\Temp\smart-ls.err' -ErrorAction SilentlyContinue
