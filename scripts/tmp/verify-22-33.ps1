Write-Host -NoNewline 'SMART='; ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt'; Write-Host ''
Write-Host -NoNewline 'SEPIDZ='; ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt'; Write-Host ''
Write-Host -NoNewline 'REPO='; Write-Host (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
$py = @'
import os
r=open("/usr/local/bin/laptop-exec","rb").read()
print("LE_CR", r.count(b"\r"), "len", len(r))
print("HAS_DIAG", os.path.isfile("/usr/local/share/claude-client/connect-diagnostic.ps1"))
print("HAS_UPDATE", os.path.isfile("/usr/local/share/claude-client/connect-update.ps1"))
print("FARZAD_LE_CR", open("/home/farzadb/.local/bin/laptop-exec","rb").read().count(b"\r"))
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
Write-Host 'SEPIDZ_CHECK:'
ssh -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "echo $b64 | base64 -d | python3"
