Write-Host '--- powershell with Claude/connect in cmdline ---'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect|claude-connect|Claude-Code' } |
  ForEach-Object {
    $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    $ws = if ($p) { [math]::Round($p.WorkingSet64/1MB,1) } else { '?' }
    $pm = if ($p) { [math]::Round($p.PrivateMemorySize64/1MB,1) } else { '?' }
    $c = $_.CommandLine
    if ($c.Length -gt 200) { $c = $c.Substring(0,200)+'...' }
    "pid=$($_.ProcessId) WS=$ws PM=$pm  $c"
  }
Write-Host '--- ssh -R tunnels ---'
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match '-R ' } |
  ForEach-Object {
    $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    $ws = if ($p) { [math]::Round($p.WorkingSet64/1MB,1) } else { '?' }
    "pid=$($_.ProcessId) WS=$ws  $($_.CommandLine)"
  }
Write-Host '--- counts ---'
$ssh = @(Get-Process ssh -ErrorAction SilentlyContinue).Count
$sshd = @(Get-Process sshd -ErrorAction SilentlyContinue).Count
$ps = @(Get-Process powershell -ErrorAction SilentlyContinue).Count
$cur = @(Get-Process Cursor -ErrorAction SilentlyContinue).Count
"ssh=$ssh sshd=$sshd powershell=$ps Cursor=$cur"
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
if (Test-Path $log) {
  $len = (Get-Item $log).Length
  "day_log_bytes=$len day_log_MB=$([math]::Round($len/1MB,2))"
}
