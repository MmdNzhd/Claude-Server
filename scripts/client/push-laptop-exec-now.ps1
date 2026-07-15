# Push laptop-exec bundle to YOUR server user (no sudo). Run after repo pull.
$dir = 'D:/Smart/Claude-Code-Server/scripts/server'
$files = @(
  @('laptop-exec.sh', '~/.local/bin/laptop-exec'),
  @('laptop-exec-setup.sh', '~/.local/bin/laptop-exec-setup'),
  @('cursor-rules/laptop-exec.mdc', '~/.cursor/rules/laptop-exec.mdc'),
  @('skills/laptop-exec/SKILL.md', '~/.cursor/skills/laptop-exec/SKILL.md'),
  @('cursor-hooks/laptop-exec-guard.sh', '~/.cursor/hooks/laptop-exec-guard.sh')
)
foreach ($f in $files) {
  $src = Join-Path $dir $f[0]
  if (Test-Path $src) {
    scp -o BatchMode=yes -q $src ("claude-server:" + $f[1])
    Write-Host "pushed $($f[0])"
  }
}
ssh claude-server 'chmod +x ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.cursor/hooks/laptop-exec-guard.sh 2>/dev/null; ~/.local/bin/laptop-exec-setup --user 2>/dev/null; echo OK'
