$root = 'D:\Smart\Claude-Code-Server'
foreach ($rel in @('scripts\server\claude-mount.sh','scripts\server\laptop-exec.sh','scripts\server\laptop-exec-setup.sh','scripts\server\claude-self-heal.sh')) {
  Write-Host "==== $rel ===="
  $i=0
  Get-Content (Join-Path $root $rel) | ForEach-Object {
    $i++
    if ($_ -match 'mountpoint|_in_proc_mounts|_is_mounted\(\)') {
      Write-Host ("{0}:{1}" -f $i, $_.TrimEnd())
    }
  }
}
# ensure _is_mounted uses _in_proc_mounts
$cm = Get-Content "$root\scripts\server\claude-mount.sh" -Raw
if ($cm -notmatch '_in_proc_mounts\(\)') { throw 'missing helper' }
if ($cm -match '(?m)^[^#\n]*mountpoint -q') { throw 'bare mountpoint remains' }
Write-Host 'VERIFY_OK'
