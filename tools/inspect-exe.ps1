$ErrorActionPreference='Continue'
$paths = @(
  'C:\Users\Smart\Downloads\claude-code-client-20260715.QUARANTINE-DO-NOT-RUN-20260721-214141\windows\Claude-Connect.exe',
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
)
foreach ($p in $paths) {
  Write-Host ("=== {0} ===" -f $p)
  if (-not (Test-Path -LiteralPath $p)) { Write-Host 'missing'; continue }
  $i = Get-Item -LiteralPath $p
  Write-Host ("len={0} mtime={1}" -f $i.Length, $i.LastWriteTime)
  $fs = [IO.File]::OpenRead($p)
  $buf = New-Object byte[] 64
  $n = $fs.Read($buf,0,64)
  $fs.Close()
  $hex = ($buf[0..([Math]::Min(15,$n-1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
  Write-Host ("head16={0}" -f $hex)
  $ascii = -join ($buf[0..([Math]::Min(63,$n-1))] | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) {[char]$_} else {'.'} })
  Write-Host ("ascii={0}" -f $ascii)
  try {
    $h = Get-FileHash -LiteralPath $p -Algorithm SHA256
    Write-Host ("sha256={0}" -f $h.Hash)
  } catch { Write-Host $_.Exception.Message }
}

# Try Desktop EXE as admin instead? User asked for quarantine path specifically.
# Also try cmd /c start
Write-Host '=== try cmd start quarantine exe ==='
$exe = $paths[0]
$p2 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c','start','','/wait',"`"$exe`"") -PassThru -Wait -WindowStyle Hidden
Write-Host ("cmd exit={0}" -f $p2.ExitCode)
