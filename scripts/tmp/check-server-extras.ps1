$root='D:\Smart\Claude-Code-Server\scripts\server'
@(
 'laptop-exec.sh','cursor-rules\laptop-exec.mdc','skills\laptop-exec\SKILL.md',
 'cursor-hooks\laptop-exec-guard.sh','cursor-hooks\hooks-user.json'
) | ForEach-Object {
  $p=Join-Path $root $_
  Write-Output ("{0} exists={1}" -f $_, (Test-Path $p))
}
