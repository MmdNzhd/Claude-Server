$ErrorActionPreference='Continue'
Write-Host '=== try claude-server alias (mux) ==='
$cmds = @(
  'hostname; whoami; tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt',
  'ss -tn state established "( sport = :22 )" | wc -l',
  'ps -ef | grep -c "[s]shd"'
)
foreach ($c in $cmds) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName='ssh'
  $psi.Arguments="-o BatchMode=yes -o ConnectTimeout=10 claude-server $c"
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $p=[Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(25000)) { try{$p.Kill()}catch{}; Write-Host "TIMEOUT for: $c" }
  else {
    Write-Host ("CMD: $c")
    Write-Host ("  exit=$($p.ExitCode) out=$($p.StandardOutput.ReadToEnd().Trim())")
    $e=$p.StandardError.ReadToEnd().Trim(); if($e){ Write-Host "  err=$e" }
  }
}

# Show ssh config for claude-server
Write-Host '=== ssh config Host claude-server ==='
$cfg = Join-Path $env:USERPROFILE '.ssh\config'
if (Test-Path $cfg) {
  $lines = Get-Content $cfg
  $print=$false
  foreach ($ln in $lines) {
    if ($ln -match '^\s*Host\s+') { $print = ($ln -match 'claude-server') }
    if ($print) { Write-Host $ln; if ($ln -match '^\s*Host\s+' -and $ln -notmatch 'claude-server' -and $script:seen) { break } }
  }
}
# Also list ControlPath sockets
Write-Host '=== control sockets ==='
Get-ChildItem (Join-Path $env:USERPROFILE '.ssh') -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'control|mux|cm-' } |
  ForEach-Object { $_.FullName }
Get-ChildItem $env:TEMP -Filter '*ssh*' -ErrorAction SilentlyContinue | Select-Object -First 20 Name
