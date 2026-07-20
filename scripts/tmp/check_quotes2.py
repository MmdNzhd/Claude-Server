from pathlib import Path
lines = Path('scripts/server/claude-mount.sh').read_text().splitlines()
l = lines[232]  # 233
print('LEN', len(l))
print(repr(l))
in_sq = in_dq = False
for j, c in enumerate(l):
    prev_sq, prev_dq = in_sq, in_dq
    if in_sq:
        if c == "'":
            in_sq = False
        continue
    if in_dq:
        if c == '\\':
            continue  # simplified
        if c == '"':
            in_dq = False
        continue
    if c == "'":
        in_sq = True
    elif c == '"':
        in_dq = True
    if c in "'\"" or j > len(l)-15:
        print(j, repr(c), 'sq', in_sq, 'dq', in_dq)

# Critical test: does bash see _emit as a function after loading the real file's function section?
import subprocess, tempfile, os
text = Path('scripts/server/claude-mount.sh').read_text()
# Run bash to only define functions then declare -F: hijack by appending
script = text + '\n' + '''
if declare -F _emit_git_hide_warn >/dev/null; then echo HAS_EMIT; else echo NO_EMIT; fi
if declare -F _win_hide_git_and_create_stubs >/dev/null; then echo HAS_WIN; else echo NO_WIN; fi
# call win hide with empty tunnel so ps is skipped early? still runs emit
LAPTOP_USER=Smart TUNNEL_PORT=21002 GIT_MODE=hide LAPTOP_OS=windows
ps_out=$'GIT_HIDE:skip\\r'
# direct call
_emit_git_hide_warn "$ps_out" || echo emit_call_ec=$?
'''
p = Path('scripts/tmp/_mount_load_test.sh')
p.write_text(script, encoding='utf-8', newline='\n')
r = subprocess.run(['bash', str(p), 'up', 'deploy'], capture_output=True, text=True, timeout=5)
print('--- stdout ---')
print(r.stdout[-1000:])
print('--- stderr ---')
print(r.stderr[-1000:])
print('ec', r.returncode)
