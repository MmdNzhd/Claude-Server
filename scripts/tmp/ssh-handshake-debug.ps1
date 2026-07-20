$ErrorActionPreference='Continue'

function Get-Banner([string]$ip) {
  $c = New-Object System.Net.Sockets.TcpClient
  $iar = $c.BeginConnect($ip, 22, $null, $null)
  if (-not $iar.AsyncWaitHandle.WaitOne(5000,$false)) { Write-Host "$ip banner=CONNECT_TIMEOUT"; return }
  $c.EndConnect($iar)
  $stream = $c.GetStream()
  $stream.ReadTimeout = 5000
  $buf = New-Object byte[] 256
  try {
    $n = $stream.Read($buf, 0, $buf.Length)
    $s = [Text.Encoding]::ASCII.GetString($buf,0,$n).Trim()
    Write-Host "$ip banner=$s"
  } catch {
    Write-Host "$ip banner_read_err=$($_.Exception.Message)"
  }
  $c.Close()
}
Get-Banner '192.168.210.240'
Get-Banner '192.168.250.70'

Write-Host '=== try ssh with -vvv capturing early ==='
$key = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
$log = Join-Path $env:TEMP 'ssh-vvv-sepidz.txt'
if (Test-Path $log) { Remove-Item $log -Force }
$args = @(
  '-vvv','-F','NUL',
  '-o','BatchMode=yes','-o','IdentitiesOnly=yes','-i',$key,
  '-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL',
  '-o','ConnectTimeout=8','-o','GSSAPIAuthentication=no',
  '-o','PreferredAuthentications=publickey',
  'sepidz@192.168.250.70','echo PONG'
)
$p = Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardError $log -RedirectStandardOutput (Join-Path $env:TEMP 'ssh-vvv-out.txt')
if (-not $p.WaitForExit(20000)) { try{$p.Kill()}catch{}; Write-Host 'killed after 20s' }
Write-Host '--- vvv log (first 80 lines) ---'
Get-Content $log -ErrorAction SilentlyContinue | Select-Object -First 80

Write-Host '=== python ssh? ==='
python --version 2>&1
pip show paramiko 2>&1 | Select-Object -First 3
