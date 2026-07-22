# Try to identify mutex owner by checking which connect.ps1 PIDs are alive and their start order
$held = $false
try {
  $m = New-Object System.Threading.Mutex($false, 'Global\ClaudeConnect')
  $held = -not $m.WaitOne(0)
  if (-not $held) { $m.ReleaseMutex() }
  $m.Close(); $m.Dispose()
} catch {}
Write-Output "Global_ClaudeConnect_held=$held"

$procs = Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'connect\.ps1' } |
  Select-Object ProcessId, CreationDate, CommandLine |
  Sort-Object CreationDate

foreach ($p in $procs) {
  $ver = 'unknown'
  if ($p.CommandLine -match 'connect\.ps1') {
    $dir = ($p.CommandLine -replace '.*-File\s+', '' -replace '\s+connect\.ps1.*','').Trim('"')
    $vf = Join-Path $dir 'connect-version.txt'
    if (Test-Path $vf) { $ver = (Get-Content $vf -Raw).Trim() }
  }
  Write-Output ("PID={0} started={1} ver={2}" -f $p.ProcessId, $p.CreationDate, $ver)
}
