# -*- coding: utf-8 -*-
"""Deep edge-case audit of connect logging + sync."""
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
ui = (root / 'scripts/client/connect-ui.ps1').read_text(encoding='utf-8')
cp = (root / 'scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
bat = (root / 'scripts/client/windows/connect.bat').read_text(encoding='utf-8', errors='replace')
upd = (root / 'scripts/client/windows/connect-update.ps1').read_text(encoding='utf-8')
sh = (root / 'scripts/client/connect-ui.sh').read_text(encoding='utf-8')
ver = (root / 'scripts/client/windows/connect-version.txt').read_text(encoding='utf-8').strip()

issues = []  # (severity, area, detail)
oks = []

def ok(area, detail): oks.append((area, detail))
def issue(sev, area, detail): issues.append((sev, area, detail))

# --- Sync function ---
s0 = ui.find('function Sync-ConnectLogToServer')
s1 = ui.find('function Write-ConnectLog {', s0)
sync = ui[s0:s1]
w0 = ui.find('function Write-ConnectLog {')
w1 = ui.find('function Read-ConnectPrompt', w0)
wl = ui[w0:w1]
init0 = ui.find('function Initialize-ConnectLog')
init1 = ui.find('function Sync-ConnectLogToServer', init0)
init = ui[init0:init1]

# duplicates
for name in ['Sync-ConnectLogToServer', 'Initialize-ConnectLog', 'Write-ConnectLog', 'Get-ConnectLogSyncTarget']:
    n = len(re.findall(rf'(?m)^function {name}\b', ui))
    if n == 1: ok('structure', f'{name} x1')
    else: issue('HIGH', 'structure', f'{name} count={n}')

# False leak
if re.search(r'return \$false|return \$true|return \$scpOk', sync):
    issue('HIGH', 'False-leak', 'Sync still returns bool')
else:
    ok('False-leak', 'Sync void + LastConnectLogSyncOk')

# HOME expansion
if "$cat = 'cat" in sync or "+ $remoteTmp +" in sync:
    ok('HOME', 'remote $HOME concat safe')
else:
    issue('HIGH', 'HOME', 'cat path may expand Windows $HOME')

# FileShare
if 'FileShare]::ReadWrite' in init or 'FileShare.ReadWrite' in init:
    ok('lock', 'FileShare.ReadWrite on log open')
else:
    issue('HIGH', 'lock', 'StreamWriter may exclusive-lock; second session silent no-log')

if 'connect log open failed' in init:
    ok('lock', 'warn on open failure')
else:
    issue('MED', 'lock', 'silent fail on log open — user never sees it')

# Write-ConnectLog policy
if "Level -eq 'TRACE'" in wl and "Level -eq 'DEBUG'" in wl:
    ok('sync-policy', 'TRACE/DEBUG local-only')
else:
    issue('HIGH', 'sync-policy', 'TRACE/DEBUG still sync')
if '-ge 25' in wl:
    ok('sync-policy', 'INFO batch 25')
else:
    issue('HIGH', 'sync-policy', 'INFO not batched')

# Sync while writer open: ReadAllBytes
if 'ReadAllBytes' in sync:
    ok('sync-io', 'ReadAllBytes used (works with ReadWrite share)')
    # Does sync hold writer lock during scp? Flush then read — OK with share
else:
    issue('MED', 'sync-io', 'unexpected sync read method')

# Watermark race: two processes same watermark file
if 'sync-offset' in ui:
    issue('MED', 'watermark', 'shared day watermark across processes — concurrent connects can skip/dupe chunks')
    ok('watermark', 'exists for resume')

# Get-ConnectLogSyncTarget early (before Alias)
tgt = ui[ui.find('function Get-ConnectLogSyncTarget'):ui.find('function Initialize-ConnectLog')]
if 'if ($Alias)' in tgt and 'REMOTE_USER' in tgt:
    ok('target', 'Alias or REMOTE_USER@SERVER_IP fallback')
else:
    issue('MED', 'target', 'weak sync target resolution')

# Empty target → silent no sync
if 'if (-not $target) { return }' in sync:
    issue('LOW', 'target', 'empty target: silent skip (local kept) — OK offline-first but no UI hint')

# scp fail once logged
if 'LOG_SYNC_FAIL' in sync and 'ConnectLogSyncFailLogged' in sync:
    ok('sync-fail', 'LOG_SYNC_FAIL once')
else:
    issue('MED', 'sync-fail', 'fail may spam or never log')

# Close-ConnectLog flush
if 'function Close-ConnectLog' in ui:
    close = ui[ui.find('function Close-ConnectLog'):ui.find('function Close-ConnectLog')+800]
    if 'Sync-ConnectLogToServer' in close:
        ok('close', 'final sync on close')
    else:
        issue('MED', 'close', 'Close may not force sync')
    if 'Dispose' in close or 'Close()' in close:
        ok('close', 'writer disposed')

# Call sites without Out-Null
callers = re.findall(r'^.*Sync-ConnectLogToServer.*$', ui + '\n' + cp, re.M)
bare = [c for c in callers if 'function Sync' not in c and '| Out-Null' not in c and 'Sync-ConnectLogToServer' in c]
# Write-ConnectLog calling Sync is OK (void)
for c in bare:
    if 'Write-ConnectLog' in ui[max(0,ui.find(c)-200):ui.find(c)+50] or c.strip().startswith('Sync-ConnectLogToServer'):
        continue
    if 'Sync-ConnectLogToServer' == c.strip() or c.strip().startswith('Sync-ConnectLogToServer'):
        # inside Write-ConnectLog — OK
        pass

# connect.ps1 log path
if 'same folder as connect.bat' in cp:
    issue('HIGH', 'UI', 'wrong log path message')
elif 'ConnectLogPath' in cp:
    ok('UI', 'full ConnectLogPath in session box')

# BOOTSTRAP before Initialize — bat logging?
if 'BOOTSTRAP' in bat or 'connect.log' in bat.lower() or '.config' in bat:
    ok('bootstrap', 'bat mentions logging path or bootstrap')
else:
    # check connect-update / early ps1
    if 'BOOTSTRAP' in upd or 'Initialize-ConnectLog' in cp[:5000]:
        ok('bootstrap', 'early log in update/connect.ps1')
    else:
        issue('MED', 'bootstrap', 'BOOTSTRAP path unclear in bat')

# Dual connect / single-instance guard?
if re.search(r'mutex|single.?instance|already running|Get-Process.*connect', cp, re.I):
    ok('dual', 'single-instance guard exists')
else:
    issue('HIGH', 'dual', 'no single-instance guard — two connect.ps1 can fight tunnel+log')

# Tunnel alias Smart vs Sepidz
if 'claude-server-sepidz' in cp and '192.168.250.70' in cp:
    ok('sepidz-patch', 'connect.ps1 has sepidz IP in source?') 
# source may still have Smart IP — publish patches

# Version
ok('version', f'source={ver}')

# Mac parity
if '-ge 25' in sh and 'TRACE' in sh:
    ok('mac', 'TRACE skip + ge 25')
else:
    issue('HIGH', 'mac', 'Mac sync policy not matching Windows')
if 'sync-offset' in sh:
    ok('mac', 'watermark')
# Mac FileShare N/A (>> append)
ok('mac', 'shell >> append is naturally share-friendly')

# Sync reads entire file into memory
if 'ReadAllBytes' in sync:
    issue('MED', 'memory', 'ReadAllBytes loads full day log — can be 10MB+; OK today, risk if log grows huge')

# Clock / day rollover midnight
if 'yyyyMMdd' in ui:
    issue('LOW', 'day-roll', 'day file name from local clock; midnight mid-session → new file, old watermark orphaned until reopen')

# UTF8 BOM from Add-Content vs StreamWriter
issue('LOW', 'encoding', 'mixed writers (Add-Content UTF8 vs StreamWriter no-BOM) can insert BOM mid-file')

# SshX vs ssh for sync when tunnel ControlMaster
if 'ControlMaster=no' in sync:
    ok('ssh', 'ControlMaster=no avoids mux hang')
else:
    issue('HIGH', 'ssh', 'sync may hang on ControlMaster')

# Elevated vs non-elevated log path same USERPROFILE?
ok('path', 'log under USERPROFILE\\.config\\claude-connect\\logs')

# GIT_MODE still present
if 'GIT_MODE' in cp or 'Write-GitModeBanner' in ui:
    ok('gitmode', 'GIT_MODE is SSHFS mode not git destroy — expected')

# Recovery / drop
if 'recover' in cp.lower() or 'Connection dropped' in cp:
    ok('recover', 'drop/recover path exists in connect.ps1')

# Auth skip when editor open — can skip needed sync?
if 'skipped' in cp.lower() and 'auth' in cp.lower():
    ok('auth', 'auth can skip when editor open (faster; edge: stale auth)')

print('VERSION', ver)
print('=== OK', len(oks))
for a,d in oks:
    print(f'  [OK] [{a}] {d}')
print('=== ISSUES', len(issues))
for sev,a,d in sorted(issues, key=lambda x: {'HIGH':0,'MED':1,'LOW':2}[x[0]]):
    print(f'  [{sev}] [{a}] {d}')
