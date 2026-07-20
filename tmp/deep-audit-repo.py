from pathlib import Path
import re, subprocess, sys
root = Path(r'D:\Smart\Claude-Code-Server')
ok=fail=0
def chk(n,c,d=''):
    global ok,fail
    if c: ok+=1; print('PASS',n,d)
    else: fail+=1; print('FAIL',n,d)

# versions
for rel, needle in [
    ('scripts/client/mac/connect.sh', "CONNECT_VERSION='20260717.31'"),
    ('scripts/client/mac/connect-version.txt', '20260717.31'),
    ('scripts/client/windows/connect-version.txt', '20260717.31'),
    ('scripts/client/windows/connect.ps1', "ConnectVersion = '20260717.31'"),
    ('docs/client-connect.md', '**Current client version:** **`20260717.31`**'),
    ('publish/README.txt', '20260717.31'),
    ('publish/README-sepidz.txt', '20260717.31'),
    ('CLAUDE.md', "ConnectVersion = '20260717.31'"),
]:
    t = (root/rel).read_text(encoding='utf-8')
    chk('ver_'+Path(rel).name, needle in t)

gm=(root/'scripts/client/git-mode.sh').read_text(encoding='utf-8')
el=(root/'scripts/client/editor-launch.sh').read_text(encoding='utf-8')
cs=(root/'scripts/client/mac/connect.sh').read_text(encoding='utf-8')
ps=(root/'scripts/client/cursor-auth-laptop.ps1').read_text(encoding='utf-8')
cc=(root/'docs/client-connect.md').read_text(encoding='utf-8')
pilot=(root/'scripts/server/CURSOR-AUTH-PILOT.md').read_text(encoding='utf-8')
claude=(root/'CLAUDE.md').read_text(encoding='utf-8')
block=el[el.find('remote_editor_on_correct_folder'):el.find('remote_editor_in_agent_home')]

for n,c in [
 ('repo_machineid_write','write_cursor_profile_machineid' in gm),
 ('repo_skip_heal','machineid healed' in gm),
 ('repo_relaunch','CURSOR_AUTH_RELAUNCH' in cs and 'CURSOR_AUTH_RELAUNCH' in el),
 ('repo_full_path','full remote_path' in el),
 ('repo_no_uri_only','uri_needle' not in block),
 ('repo_win_mid','Write-CursorProfileMachineId' in ps),
 ('repo_win_skip','machineid healed' in ps),
 ('doc_machineid','machineid' in cc.lower()),
 ('doc_relaunch','CURSOR_AUTH_RELAUNCH' in cc),
 ('doc_access_ssh','access_ssh-disabled' in cc),
 ('doc_login_troubleshoot','asks to log in' in cc.lower()),
 ('doc_no_current_24','Current client version:** **`20260717.24`' not in cc),
 ('pilot_machineid','machineid' in pilot.lower()),
 ('claude_selfheal_mid','machineid' in claude.lower()),
 ('claude_access_ssh','access_ssh-disabled' in claude),
]:
    chk(n,c)

# Windows requires path+uri
elps=(root/'scripts/client/editor-launch.ps1').read_text(encoding='utf-8')
chk('win_both_needles', 'uriNeedle' in elps and 'pathNeedle' in elps)

# Run test
r=subprocess.run(['powershell','-NoProfile','-File', str(root/'scripts/client/tests/test-cursor-auth-merge.ps1')], capture_output=True, text=True)
chk('test_auth_merge', r.returncode==0, (r.stdout+r.stderr)[-200:].replace('\n',' | '))

print('PART3', ok, 'pass', fail, 'fail')
sys.exit(1 if fail else 0)
