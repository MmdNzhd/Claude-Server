$root = 'D:\Smart\Claude-Code-Server'
$files = @(
  'scripts\server\claude-self-heal.sh',
  'scripts\server\laptop-exec-setup.sh',
  'scripts\server\laptop-exec.sh',
  'scripts\server\claude-mount.sh',
  'scripts\server\claude-automount.sh'
)
foreach ($rel in $files) {
  $p = Join-Path $root $rel
  Write-Host "==== $rel ===="
  $i=0
  Get-Content $p | ForEach-Object {
    $i++
    if ($_ -match 'mountpoint') {
      Write-Host ("{0}:{1}" -f $i, $_.TrimEnd())
    }
  }
}
