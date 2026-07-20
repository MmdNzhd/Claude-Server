$root = 'D:\Smart\Claude-Code-Server'
$files = @('scripts\server\claude-mount.sh','scripts\server\laptop-exec.sh')
foreach ($rel in $files) {
  Write-Host "==== $rel ===="
  $i=0
  Get-Content (Join-Path $root $rel) | ForEach-Object {
    $i++
    if ($_ -match '_is_mount|_mounted|proc/mounts|mountpoint') {
      Write-Host ("{0}:{1}" -f $i, $_.TrimEnd())
    }
  }
}
