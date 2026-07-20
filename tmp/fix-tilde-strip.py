from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
gm = root / 'scripts/client/git-mode.sh'
t = gm.read_text(encoding='utf-8')

old = '''    # Normalize: callers pass ~/path; never allow $HOME/~/path on the server.
    case "$remote" in
        '~/'*) remote="${remote#~/}" ;;
        '~')   remote='' ;;
    esac
    case "$remote" in
        '')          rpath='\$HOME' ;;
        '$HOME/'*)   rpath="$remote" ;;
        /home/*)     rpath="$remote" ;;
        /*)          rpath="$remote" ;;
        *)           rpath="\$HOME/$remote" ;;
    esac'''

new = '''    # Normalize: callers pass ~/path; never allow $HOME/~/path on the server.
    # IMPORTANT: do NOT use ${remote#~/} — bash tilde-expands the # pattern to $HOME/,
    # so the strip fails and rpath becomes $HOME/~/... (literal directory "~/").
    case "$remote" in
        '~/'*) remote="${remote:2}" ;;
        '~')   remote='' ;;
    esac
    case "$remote" in
        '')          rpath='\$HOME' ;;
        '$HOME/'*)   rpath="$remote" ;;
        /home/*)     rpath="$remote" ;;
        /*)          rpath="$remote" ;;
        *)           rpath="\$HOME/$remote" ;;
    esac'''

if old not in t:
    raise SystemExit('push normalize block missing')
t = t.replace(old, new, 1)

# Also fix scp_dest#\$HOME/ - use safer strip
old_scp = '''    case "$scp_dest" in
        ''|'$HOME') scp_dest='~' ;;
        '$HOME/'*)  scp_dest="~/${scp_dest#\$HOME/}" ;;
        /*)         ;;
        *)          scp_dest="~/$scp_dest" ;;
    esac'''
new_scp = '''    case "$scp_dest" in
        ''|'$HOME') scp_dest='~' ;;
        '$HOME/'*)  scp_dest="~/${scp_dest:6}" ;;  # len('$HOME/')==6; avoid #~/ tilde pitfall
        /*)         ;;
        *)          scp_dest="~/$scp_dest" ;;
    esac'''
if old_scp not in t:
    raise SystemExit('scp case missing')
t = t.replace(old_scp, new_scp, 1)

gm.write_bytes(t.replace('\r\n','\n').replace('\r','\n').encode())
print('OK git-mode tilde strip')

# bump .32
for rel in [
    'scripts/client/mac/connect.sh',
    'scripts/client/windows/connect.ps1',
    'scripts/client/mac/connect-version.txt',
    'scripts/client/windows/connect-version.txt',
    'docs/client-connect.md',
    'publish/README.txt',
    'publish/README-sepidz.txt',
    'CLAUDE.md',
    'scripts/server/CURSOR-AUTH-PILOT.md',
]:
    p = root / rel
    if not p.exists():
        continue
    c = p.read_text(encoding='utf-8')
    c2 = c.replace('20260717.31', '20260717.32')
    if c2 != c:
        if rel.endswith('.sh') or 'mac/connect' in rel:
            p.write_bytes(c2.replace('\r\n','\n').replace('\r','\n').encode())
        else:
            p.write_text(c2, encoding='utf-8', newline='\n')
        print('bumped', rel)

# Doc note about tilde pitfall in client-connect troubleshooting
cc = root / 'docs/client-connect.md'
c = cc.read_text(encoding='utf-8')
if 'HOME/~' not in c and '$HOME/~' not in c:
    c = c.replace(
        '| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |',
        '| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |\n'
        '| Server path `$HOME/~/...` or leftover `~/` under home | Fixed in v20260717.32+ (`${var#~/}` tilde pitfall); admin may `rm -rf ~/\\~` leftover dir |'
    )
    cc.write_text(c, encoding='utf-8', newline='\n')
    print('OK doc tilde row')

# Ensure connect.sh LF + version
p = root / 'scripts/client/mac/connect.sh'
p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n').replace(b'\r', b'\n'))
print('done')
