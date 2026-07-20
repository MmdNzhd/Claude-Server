# Copy locked log via .NET FileShare.ReadWrite
$src = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst = Join-Path $env:TEMP 'connect-log-copy.log'
$fs = [System.IO.File]::Open($src, 'Open', 'Read', 'ReadWrite')
try {
  $out = [System.IO.File]::Create($dst)
  try { $fs.CopyTo($out) } finally { $out.Close() }
} finally { $fs.Close() }
Write-Host ("copied bytes={0}" -f (Get-Item $dst).Length)
Write-Host 'LOG_SYNC lines:'
Select-String -Path $dst -Pattern 'LOG_SYNC' | Select-Object -Last 10 | ForEach-Object { $_.Line }
Write-Host 'level counts:'
Select-String -Path $dst -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Group-Object | Sort-Object Count -Descending | Format-Table Name,Count -AutoSize
Remove-Item $dst -Force
