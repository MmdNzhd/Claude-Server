# Push laptop-exec bundle to YOUR server user (no sudo). Run after repo pull.
# Windows + Mac clients both land files on the Linux server; hooks use fail-open WRAP.
$dir = 'D:/Smart/Claude-Code-Server/scripts/server'
$files = @(
  @('laptop-exec.sh', '~/.local/bin/laptop-exec'),
  @('laptop-exec-setup.sh', '~/.local/bin/laptop-exec-setup'),
  @('cursor-rules/laptop-exec.mdc', '~/.cursor/rules/laptop-exec.mdc'),
  @('skills/laptop-exec/SKILL.md', '~/.cursor/skills/laptop-exec/SKILL.md'),
  @('cursor-hooks/laptop-exec-guard.sh', '~/.cursor/hooks/laptop-exec-guard.sh'),
  @('cursor-hooks/laptop-exec-guard-wrap.sh', '~/.cursor/hooks/laptop-exec-guard-wrap.sh'),
  @('cursor-hooks/laptop-exec-shell-scan.py', '~/.cursor/hooks/laptop-exec-shell-scan.py'),
  @('cursor-hooks/laptop-exec-session.sh', '~/.cursor/hooks/laptop-exec-session.sh')
)
foreach ($f in $files) {
  $src = Join-Path $dir $f[0]
  if (Test-Path $src) {
    scp -o BatchMode=yes -q $src ("claude-server:" + $f[1])
    Write-Host "pushed $($f[0])"
  }
}
ssh claude-server @'
chmod +x ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup \
  ~/.cursor/hooks/laptop-exec-guard.sh ~/.cursor/hooks/laptop-exec-guard-wrap.sh \
  ~/.cursor/hooks/laptop-exec-shell-scan.py ~/.cursor/hooks/laptop-exec-session.sh 2>/dev/null
# Absolute hooks.json (fail-open wrap) - never use relative ./hooks from hooks-user.json
h="$HOME/.cursor/hooks"
mkdir -p "$h"
python3 - <<PY
import json, os
home = os.path.expanduser("~")
h = os.path.join(home, ".cursor", "hooks")
wrap = os.path.join(h, "laptop-exec-guard-wrap.sh")
sess = os.path.join(h, "laptop-exec-session.sh")
cfg = {
  "version": 1,
  "hooks": {
    "sessionStart": [{"command": sess}],
    "beforeShellExecution": [{"command": wrap}],
    "preToolUse": [{"command": wrap, "matcher": "Grep|Glob|Shell|Read|Write|Edit|StrReplace|Delete|Task"}],
  },
}
path = os.path.join(home, ".cursor", "hooks.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("hooks.json ->", wrap)
PY
~/.local/bin/laptop-exec-setup --user 2>/dev/null || true
echo OK
'@
