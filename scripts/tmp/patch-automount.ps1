$ErrorActionPreference = 'Stop'
$p = 'D:\Smart\Claude-Code-Server\scripts\server\claude-automount.sh'
$c = [IO.File]::ReadAllText($p)
if ($c -match 'VSCODE_RESOLVING_ENVIRONMENT') {
    Write-Host 'already patched'
    exit 0
}
$pattern = '(?s)# Cursor/VS Code spawn bash -ilc to resolve the shell environment\..*?elif \[ -x "\$HOME/\.local/bin/claude-self-heal" \]; then\r?\n    "\$HOME/\.local/bin/claude-self-heal" --quiet 2>/dev/null \|\| true\r?\nfi'
$replacement = @'
# Cursor/VS Code spawn bash -ilc to resolve the shell environment. That must not
# re-run mount/auth/recover (~20s). connect.bat already mounted and synced auth.
# Early resolve often has NONE of VSCODE_IPC_HOOK_CLI / TERM_PROGRAM set yet.
if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] || [ -n "${CURSOR_AGENT:-}" ] || [ "${TERM_PROGRAM:-}" = "vscode" ] \
    || [ -n "${VSCODE_RESOLVING_ENVIRONMENT:-}" ] || [ -n "${VSCODE_PID:-}" ] \
    || [ -n "${CURSOR_TRACE_ID:-}" ]; then
    exit 0
fi
_ppargs=$(ps -o args= -p "${PPID:-0}" 2>/dev/null || true)
case "$_ppargs" in
    *cursor-server*|*vscode-server*|*bootstrap-fork*|*server-main.js*|*remote-cli*)
        exit 0
        ;;
esac

# Bound all login-path work so a hung auth/heal cannot break Cursor shell resolve.
# Server-wide OAuth: keep credentials.json empty and sync token into settings.json.
if [ -x /usr/local/bin/claude-auth-sync ]; then
    timeout 4 /usr/local/bin/claude-auth-sync >/dev/null 2>&1 || true
fi

if [ -x /usr/local/bin/cursor-auth-sync ] && [ -f /etc/cursor-auth/golden/auth.json ]; then
    timeout 4 /usr/local/bin/cursor-auth-sync >/dev/null 2>&1 || true
fi

if [ -x /usr/local/bin/laptop-exec-setup ]; then
    timeout 5 /usr/local/bin/laptop-exec-setup --user >/dev/null 2>&1 || true
    timeout 5 /usr/local/bin/laptop-exec-setup --all-projects >/dev/null 2>&1 || true
fi

# Full self-heal (CRLF, Cursor git-off, conf normalize, stale mounts, shim)
if [ -x /usr/local/bin/claude-self-heal ]; then
    timeout 8 /usr/local/bin/claude-self-heal --quiet >/dev/null 2>&1 || true
elif [ -x "$HOME/.local/bin/claude-self-heal" ]; then
    timeout 8 "$HOME/.local/bin/claude-self-heal" --quiet >/dev/null 2>&1 || true
fi
'@
$new = [regex]::Replace($c, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }, 1)
if ($new -eq $c) { throw 'regex replace failed - pattern not found' }
# normalize to LF
$new = $new -replace "`r`n", "`n" -replace "`r", "`n"
[IO.File]::WriteAllText($p, $new)
Write-Host 'patched OK'
Select-String -Path $p -Pattern 'VSCODE_RESOLVING_ENVIRONMENT|timeout 8|_ppargs' | ForEach-Object { $_.Line.Trim() }
