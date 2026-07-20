# -*- coding: utf-8 -*-
from pathlib import Path
import re, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

root = Path(r'D:\Smart\Claude-Code-Server')
ui = (root/'scripts/client/connect-ui.ps1').read_text(encoding='utf-8')
cp = (root/'scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
upd = (root/'scripts/client/windows/connect-update.ps1').read_text(encoding='utf-8')
bat = (root/'scripts/client/windows/connect.bat').read_text(encoding='utf-8', errors='replace')
sh = (root/'scripts/client/connect-ui.sh').read_text(encoding='utf-8')
gm = (root/'scripts/client/git-mode.ps1').read_text(encoding='utf-8')

print('=== EDGE MATRIX ===')

checks = []

def row(sev, topic, status, detail):
    checks.append((sev, topic, status, detail))
    print(f'[{sev:4}] [{status:4}] {topic}: {detail}')

# 1 writer null mid-session — no reinit
if 'if (-not $script:ConnectLogWriter) { return }' in ui and 'Initialize-ConnectLog' not in ui[ui.find('function Write-ConnectLog'):ui.find('function Write-ConnectLog')+500]:
    row('HIGH','log-reopen','GAP','Write-ConnectLog returns if writer null; never retries open after lock clears')

# 2 BOOTSTRAP session id
if 'BOOTSTRAP' in bat or 'BOOTSTRAP' in upd:
    if 'ConnectSessionId' in upd or 'session' in upd.lower():
        row('MED','bootstrap-sid','GAP','BOOTSTRAP lines often lack session= id (harder to correlate)')
    else:
        row('MED','bootstrap-sid','GAP','BOOTSTRAP may be before session id assigned')

# 3 Update while running
if 'Updated to' in upd:
    row('HIGH','hot-update','GAP','connect-update replaces scripts under running process; in-memory code stays old until restart')

# 4 Dual Smart+Sepidz folders
row('HIGH','dual-folder','GAP','User can run sepidz AND claude-code-client connect together; tunnels/aliases collide (seen: ssh to claude-server while UI says sepidz)')

# 5 Tunnel port stale wait
if 'STALE_FORWARD' in gm or 'port still busy' in gm:
    row('MED','stale-port','KNOWN','STALE_FORWARD wait ~10s still possible; major remaining slowness')

# 6 CIM spam
if 'PERF[cim_query]' in gm or 'cim_query' in gm or 'Write-ConnectPerfLog' in ui:
    row('MED','cim-spam','KNOWN','Session loop still emits heavy DEBUG PERF/cim; local-only now but CPU/disk still busy')

# 7 Sync every WARN in hot path
row('LOW','warn-sync','OK','WARN flushes sync immediately — good for failures; rare')

# 8 scp of large chunk after long offline
row('MED','big-chunk','GAP','If watermark 0 and log 8MB+, first sync uploads whole file; can look like hang')

# 9 Midnight rollover
row('LOW','midnight','GAP','New day file mid-session without re-Initialize leaves writes on old path until restart')

# 10 Sync target Alias empty during UPDATE before conf
row('MED','early-sync','GAP','UPDATE/BOOTSTRAP sync needs REMOTE_USER@IP from conf; if conf missing, early lines stay local-only until Alias set')

# 11 Mac ge25 deployed?
row('MED','mac-deploy','CHECK','Mac policy fixed in source; confirm bundle on Sepidz has ge 25')

# 12 Elevated USERPROFILE
row('LOW','elevated','OK','elevated=yes uses same USERPROFILE for Smart user — usually OK')

# 13 Git hide mode confusion
row('LOW','git-banner','OK','GIT_MODE=hide is intentional SSHFS behavior')

# 14 Auth skip
if 'already complete' in cp or 'skipped' in cp:
    row('LOW','auth-skip','OK','Skip auth when editor open speeds up; edge: machineid heal may be skipped')

# 15 Recover reopen Cursor
row('MED','recover-open','KNOWN','Drop/recover may reopen Cursor; feels slow; logged as recover')

# 16 LOG_SYNC_FAIL then never retry until WARN
# After fail flag set, does success reset? yes ConnectLogSyncFailLogged=$false on success
if 'ConnectLogSyncFailLogged = $false' in ui or 'ConnectLogSyncFailLogged=$false' in ui:
    row('OK','sync-retry','OK','fail flag clears on success; INFO batch retries')
else:
    row('MED','sync-retry','GAP','after LOG_SYNC_FAIL may stop retrying')

# 17 FileShare + ReadAllBytes concurrent write
row('MED','torn-read','GAP','ReadAllBytes during concurrent WriteLine can tear last line; rare corruption at chunk boundary')

# 18 No flock on remote append
row('MED','remote-race','GAP','two laptops same user appending connect-DAY.log remotely can interleave lines')

# 19 connect.bat path still old folder name 20260717
row('LOW','folder-name','OK','Desktop folder name can be old; auto-update refreshes contents')

# 20 Watermark file not locked
row('MED','wm-race','GAP','two processes updating .sync-offset can skip bytes or duplicate to server')

# 21 Session status "closed"
row('LOW','status-closed','INFO','UI status closed means editor not on folder — not tunnel down')

# 22 Smart freeze
row('OK','smart-freeze','OK','publish -SepidzOnly only; Smart stays 20260717.22')

# 23 Writer AutoFlush + Sync Flush
row('OK','flush','OK','AutoFlush + Sync Flush before ReadAllBytes')

# 24 False UI
row('OK','false-ui','OK','void Sync + Out-Null callers')

# 25 HOME
row('OK','home','OK','concat remote HOME')

print('\n=== COUNTS ===')
from collections import Counter
c=Counter(x[2] for x in checks)
print(dict(c))
print('HIGH gaps:', sum(1 for x in checks if x[0]=='HIGH' and x[2]=='GAP'))
print('MED gaps:', sum(1 for x in checks if x[0]=='MED' and x[2]=='GAP'))

# concrete code refs
print('\n=== CODE REFS ===')
for pat, label in [
    (r'FileShare\]::ReadWrite', 'FileShare'),
    (r'ConnectLogWriter\) \{ return \}', 'null writer early return'),
    (r'single|mutex|AlreadyRunning', 'single instance'),
    (r'ReadAllBytes', 'ReadAllBytes'),
    (r'-ge 25', 'batch 25'),
]:
    m=re.search(pat, ui, re.I)
    print(label, 'FOUND' if m else 'MISSING')
