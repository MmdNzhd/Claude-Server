from pathlib import Path

p = Path('scripts/client/connect-ui.ps1')
t = p.read_text(encoding='utf-8')
recon = Path('scripts/tmp/reconcile_insert.ps1.frag').read_text(encoding='utf-8')
old = Path('scripts/tmp/size_verify_old.ps1.frag').read_text(encoding='utf-8')
new = Path('scripts/tmp/size_verify_new.ps1.frag').read_text(encoding='utf-8')

if 'LOG_SYNC_RECONCILE' not in t:
    needle = "        $mk = 'mkdir -p \"$HOME/.claude/logs\""
    idx = t.find(needle)
    if idx < 0:
        raise SystemExit('mk needle missing')
    t = t[:idx] + recon + t[idx:]
    print('inserted reconcile')
else:
    print('reconcile already there')

if 'LOG_SYNC_RECONCILE size_verify' not in t:
    if old not in t:
        raise SystemExit('old append block missing')
    t = t.replace(old, new, 1)
    print('patched size_verify')
else:
    print('size_verify already there')

# dedupe sshOpts after mk
dup = (
    "        $mk = 'mkdir -p \"$HOME/.claude/logs\" && chmod 700 \"$HOME/.claude\" \"$HOME/.claude/logs\" 2>/dev/null; find \"$HOME/.claude/logs\" -type f -mtime +1 -delete 2>/dev/null; true'\n"
    "        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')\n"
    "        # Bug 11: cat must surface append failure (no trailing true).\n"
)
fixed = (
    "        $mk = 'mkdir -p \"$HOME/.claude/logs\" && chmod 700 \"$HOME/.claude\" \"$HOME/.claude/logs\" 2>/dev/null; find \"$HOME/.claude/logs\" -type f -mtime +1 -delete 2>/dev/null; true'\n"
    "        # Bug 11: cat must surface append failure (no trailing true).\n"
)
if dup in t:
    t = t.replace(dup, fixed, 1)
    print('removed dup sshOpts')

# init remoteBefore if somehow missing before size_verify - ensure var exists
# after reconcile insert, remoteBefore is always set before scp path

p.write_text(t, encoding='utf-8', newline='\n')
print('wrote', p)
