$ErrorActionPreference = 'Continue'
$tmp = Join-Path $env:TEMP ('ssh-cm-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
# Windows OpenSSH prefers a path under TEMP; %C is hash of connection
$cp = Join-Path $tmp 'mux-%C'
Write-Host "ControlPath template: $cp"

# Resolve actual path after first connect is hard; use fixed %C-less path for test
$cpFixed = Join-Path $tmp 'mux-claude'
Write-Host "ControlPath fixed: $cpFixed"

Write-Host '--- start master (-MNf) ---'
$out = & ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=yes -o "ControlPath=$cpFixed" -o ControlPersist=60 -o ClearAllForwardings=yes -MNf claude-server 2>&1
Write-Host "master_out=$out ec=$LASTEXITCODE"

Write-Host '--- check ---'
$chk = & ssh -O check -o "ControlPath=$cpFixed" claude-server 2>&1
Write-Host "check=$chk ec=$LASTEXITCODE"

if ($LASTEXITCODE -ne 0) {
  Write-Host 'ControlMaster FAILED to establish'
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  exit 2
}

$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i=1; $i -le 5; $i++) {
  $r = & ssh -o BatchMode=yes -o "ControlPath=$cpFixed" -o ControlMaster=no claude-server "echo ok$i" 2>&1
  Write-Host "cmd$i ec=$LASTEXITCODE out=$r"
}
$sw.Stop()
Write-Host "mux_5_cmds_ms=$($sw.ElapsedMilliseconds)"

$sw2 = [Diagnostics.Stopwatch]::StartNew()
for ($i=1; $i -le 5; $i++) {
  $r = & ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=10 -o ClearAllForwardings=yes claude-server "echo ok$i" 2>&1
  Write-Host "nomux$i ec=$LASTEXITCODE"
}
$sw2.Stop()
Write-Host "nomux_5_cmds_ms=$($sw2.ElapsedMilliseconds)"

& ssh -O exit -o "ControlPath=$cpFixed" claude-server 2>&1 | Out-Null
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host 'DONE'
