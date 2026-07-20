$files = @(
  'D:\Smart\Claude-Code-Server\scripts\tmp\deep_plus.py',
  'D:\Smart\Claude-Code-Server\scripts\server\claude-self-heal.sh',
  'D:\Smart\Claude-Code-Server\scripts\server\laptop-exec-setup.sh',
  'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh'
)
foreach ($p in $files) {
  Write-Host "==== $p ===="
  $i = 0
  Get-Content $p | ForEach-Object {
    $i++
    if ($_ -match 'laptop-exec-setup|claude-automount|\.local/bin|GOLDEN_') {
      Write-Host ("{0}:{1}" -f $i, $_)
    }
  }
}
