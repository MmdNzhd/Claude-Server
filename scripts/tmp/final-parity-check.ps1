$ErrorActionPreference='Continue'
foreach($pair in @(
  @('Smart','smart@192.168.210.240'),
  @('Sepidz','sepidz@192.168.250.70')
)){
  $label=$pair[0]; $t=$pair[1]
  Write-Host "==== $label ===="
  & ssh -o BatchMode=yes -o ConnectTimeout=12 $t "python3 - <<'PY'
import os
ver=open('/usr/local/share/claude-client/connect-version.txt').read().strip().replace('\\r','')
print('VER',ver)
for f in ['connect-diagnostic.ps1','connect-update.ps1','server/laptop-exec.sh']:
  p='/usr/local/share/claude-client/'+f
  print(('OK' if os.path.isfile(p) else 'MISS'), f)
print('SUDOERS', os.path.isfile('/etc/sudoers.d/claude-client-deploy'))
raw=open('/usr/local/bin/laptop-exec','rb').read()
print('LAPTOP_EXEC', 'CRLF' if b'\\r' in raw else 'LF', len(raw))
PY"
}
Write-Host '==== repo harden ===='
$files=@(
 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1',
 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1',
 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh',
 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh'
)
foreach($f in $files){
  Write-Host "-- $([IO.Path]::GetFileName($f)) --"
  Select-String -Path $f -Pattern 'base64|SudoPassword \||& ssh|up to date|unreachable|_apply_git_scm|git.enabled|sed -i' | Select-Object -First 12 | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
}
# farzad git settings verify
Write-Host '==== farzad git settings ===='
& ssh -o BatchMode=yes -o ConnectTimeout=12 sepidz@192.168.250.70 "python3 - <<'PY'
import json
for p in ['/home/farzadb/mounts/frontend/.vscode/settings.json','/home/farzadb/mounts/backend/.vscode/settings.json']:
  d=json.load(open(p))
  print(p, 'git.enabled=', d.get('git.enabled'), 'auto=', d.get('git.autoRepositoryDetection'))
PY"
