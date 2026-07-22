#Requires -Version 5.1
# Deep inventory of DISTINCT problem signatures on Sepidz (today) across ALL users.
# Invoked via Windows MCP PowerShell HTTP forward from Smart server.
$ErrorActionPreference = 'Stop'
Set-Location 'D:\Smart\Claude-Code-Server'

$raw = Get-Content -LiteralPath 'publish\sepidz-deploy.local.ps1' -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$sshUser = [regex]::Match($raw, '(?m)^\s*\$SepidzSshUser\s*=\s*''([^'']*)''').Groups[1].Value
$ip = [regex]::Match($raw, '(?m)^\s*\$SepidzServerIp\s*=\s*''([^'']*)''').Groups[1].Value
if (-not $sshUser) { $sshUser = 'sepidz' }
if (-not $ip) { $ip = '192.168.250.70' }
if (-not $pw) { throw 'empty SepidzSudoPassword' }
if ($sshUser -ne 'sepidz') { throw "need user sepidz got $sshUser" }

$target = "$sshUser@$ip"
$remoteSh = "/home/$sshUser/sepidz-deep-problems.sh"
$localSh = Join-Path $env:TEMP ('sepidz-deep-' + [guid]::NewGuid().ToString('n') + '.sh')

$script = @'
#!/bin/bash
set +e
export LC_ALL=C
echo ===META===
hostname; date -u; date; whoami; id
echo ===TUNNELS===
ss -lnt 2>/dev/null | grep -E '127\.0\.0\.1:2[0-9]{4}' | head -40
echo ===LOG_FILES===
# inventory all connect/laptop-exec logs for today across /home/*
for f in /home/*/.claude/logs/connect-20260722.log /home/*/.claude/logs/laptop-exec-20260722.log; do
  [ -f "$f" ] || continue
  u=$(echo "$f" | cut -d/ -f3)
  kind=$(basename "$f")
  echo "FILE user=$u kind=$kind bytes=$(wc -c <"$f") lines=$(wc -l <"$f") mtime=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1)"
done
echo ===USERS_WITH_HOME===
ls -1 /home | tr '\n' ' '; echo

echo ===CONNECT_VERSION_BUILD_ID===
python3 - <<'PY'
import glob, re, os
from collections import defaultdict
pat_cv = re.compile(r'CONNECT_VERSION[=:]\s*([^\s,;]+)')
pat_bid = re.compile(r'BUILD_ID[=:]\s*([^\s,;]+)')
pat_script = re.compile(r'ScriptDir=([^\s]+)|CONNECT_VERSION=([^\s]+)|local_exe_drift|BOOTSTRAP|UPDATE:')
for path in sorted(glob.glob('/home/*/.claude/logs/connect-20260722.log')):
    u = path.split('/')[2]
    cvs, bids, extras = set(), set(), []
    for i, line in enumerate(open(path, errors='replace'), 1):
        for m in pat_cv.finditer(line):
            cvs.add(m.group(1).strip().strip("'\"\r"))
        for m in pat_bid.finditer(line):
            bids.add(m.group(1).strip().strip("'\"\r"))
        if 'CONNECT_VERSION' in line or 'BUILD_ID' in line or 'ScriptDir=' in line or 'BOOTSTRAP' in line:
            if len(extras) < 8:
                extras.append(f'L{i}:{line.rstrip()[:220]}')
    print(f'USER={u} CONNECT_VERSION={",".join(sorted(cvs)) or "NONE"} BUILD_ID={",".join(sorted(bids)) or "NONE"}')
    for e in extras[:5]:
        print('  '+e)
PY

echo ===DEEP_SIGNATURE_INVENTORY===
python3 - <<'PY'
import glob, re, os, json
from collections import defaultdict

# Known seed patterns + broader ERROR/WARN extractors
# Each rule: (signature_name, category, compiled_regex that matches a line and optionally captures detail)
RULES = [
    # connect / sync
    ("LOG_SYNC_FAIL", "connect", re.compile(r'LOG_SYNC_FAIL')),
    ("LOG_SYNC_ASYNC", "connect", re.compile(r'LOG_SYNC_ASYNC')),
    ("PUSH_CONF_blocked", "connect", re.compile(r'PUSH_CONF\s+blocked|Push-ServerConnectConf.*blocked', re.I)),
    ("foreign_peer", "connect", re.compile(r'foreign_peer|foreign\s+LAPTOP_USER', re.I)),
    ("TUNNEL_DROP", "connect", re.compile(r'TUNNEL_DROP|tunnel\s+drop|Test-Tunnel.*False|tunnel.*DOWN', re.I)),
    ("SESSION_STATUS_BROKEN", "connect", re.compile(r'SESSION_STATUS=BROKEN|session.*broken', re.I)),
    ("OUTDATED_SCRIPTS", "update", re.compile(r'OUTDATED_SCRIPTS|local_exe_drift')),
    ("UPDATE_UNHANDLED", "update", re.compile(r'UPDATE_UNHANDLED|UPDATE:\s')),
    ("UPDATE_swap_fail", "update", re.compile(r'swap_fail|UPDATE.*swap', re.I)),
    ("BOOTSTRAP_FAIL", "update", re.compile(r'BOOTSTRAP.*(FAIL|ERROR)|bootstrap.*fail', re.I)),
    ("mkdir_timeout", "connect", re.compile(r'mkdir_timeout')),
    ("Connection_refused", "connect", re.compile(r'Connection refused')),
    ("need_mount", "mount", re.compile(r'need_mount|need remount|NEED_REMOUNT', re.I)),
    ("SSHFS_NOT_MOUNTED", "mount", re.compile(r'SSHFS_NOT_MOUNTED|sshfs.*not.?mount|NOT_MOUNTED', re.I)),
    ("mount_zombie", "mount", re.compile(r'ZOMBIE|stale\s+mount|mount.*stale', re.I)),
    ("claude-mount_fail", "mount", re.compile(r'claude-mount.*(fail|error|refused)|error:\s+port\s+\d+\s+is\s+another\s+laptop', re.I)),
    # auth
    ("AUTH_ERROR", "auth", re.compile(r'\[ERROR\].*AUTH|AUTH ERROR|auth.*(fail|error|reject)', re.I)),
    ("machineid_file_mismatch", "auth", re.compile(r'machineid_file_mismatch')),
    ("cursor_auth", "auth", re.compile(r'cursor-auth|CURSOR_AUTH|auth\.json|state\.vscdb|golden.*auth', re.I)),
    ("sshd_auth_fail", "auth", re.compile(r'Permission denied \(publickey|authorized_keys|sshd.*(fail|reject)', re.I)),
    # proxy
    ("PROXY_HEALTH", "proxy", re.compile(r'PROXY_HEALTH')),
    ("PROXY_HEALTH_ok0", "proxy", re.compile(r'PROXY_HEALTH\s+ok=0|PROXY_HEALTH.*ok=0')),
    ("SIDECAR_ENSURE", "proxy", re.compile(r'SIDECAR_ENSURE')),
    ("CURSOR_PROXY_CLEAR", "proxy", re.compile(r'CURSOR_PROXY_CLEAR')),
    ("proxy_18998", "proxy", re.compile(r'18998|18999|sidecar', re.I)),
    # multiagent / laptop-exec
    ("multiagent", "multiagent", re.compile(r'\[multiagent\]|session slots full|mux|laptop-exec.*(DENY|timeout|BLOCK)', re.I)),
    ("slots_full", "multiagent", re.compile(r'session slots full|slots full')),
    ("laptop_exec_timeout", "multiagent", re.compile(r'laptop-exec: command timed out|LAPTOP_EXEC.*timeout', re.I)),
    ("hook_deny", "multiagent", re.compile(r'hook.*DENY|SSH-first BLOCKED|NEXT:\s*laptop-exec', re.I)),
    # generic severity
    ("VERDICT_FAIL", "connect", re.compile(r'VERDICT_CODE=(?!OK)([A-Z_]+)')),
    ("FAIL_TOKEN", "connect", re.compile(r'\bFAIL\s+([A-Z_]{3,})')),
]

# Also capture any [ERROR]/[WARN] line tokenized by a signature heuristic
LEVEL_RE = re.compile(r'\[(ERROR|WARN|WARNING|multiagent)\]')
TS_RE = re.compile(r'^(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})')
# Alternative ts formats used in connect logs
TS_RE2 = re.compile(r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)')

def extract_ts(line):
    m = TS_RE2.search(line)
    return m.group(1) if m else None

def generic_sig(line):
    """Derive a short signature from ERROR/WARN lines not matched by seeds."""
    # Strip ts / level prefix
    s = line
    s = re.sub(r'^\S+\s+', '', s, count=1)  # rough
    m = LEVEL_RE.search(line)
    level = m.group(1) if m else 'OTHER'
    # Prefer ALLCAPS tokens / known key=value
    tokens = re.findall(r'\b([A-Z][A-Z0-9_]{2,})\b', line)
    # drop noise
    noise = {'ERROR','WARN','WARNING','INFO','DEBUG','TRUE','FALSE','NULL','HTTP','SSH','SSHFS','UTC','JSON','PATH'}
    tokens = [t for t in tokens if t not in noise]
    if tokens:
        return f'GEN:{level}:{tokens[0]}', 'connect' if level != 'multiagent' else 'multiagent'
    # fallback: first 60 chars of message after level
    msg = line
    if m:
        msg = line[m.end():].strip()
    msg = re.sub(r'\s+', ' ', msg)[:60]
    return f'GEN:{level}:{msg}', 'connect'

class Hit:
    __slots__ = ('count','users','first','last','example')
    def __init__(self):
        self.count = 0
        self.users = set()
        self.first = None
        self.last = None
        self.example = None

hits = defaultdict(Hit)  # sig -> Hit
cats = {}  # sig -> category
per_user_levels = defaultdict(lambda: defaultdict(int))  # u -> level -> count
files_seen = []

def add(sig, cat, user, line, ts):
    h = hits[sig]
    h.count += 1
    h.users.add(user)
    cats[sig] = cat
    if ts:
        if h.first is None or ts < h.first:
            h.first = ts
        if h.last is None or ts > h.last:
            h.last = ts
    if h.example is None:
        h.example = line.rstrip()[:260]

# CONNECT logs
for path in sorted(glob.glob('/home/*/.claude/logs/connect-20260722.log')):
    u = path.split('/')[2]
    files_seen.append(('connect', u, path, os.path.getsize(path)))
    for line in open(path, errors='replace'):
        ts = extract_ts(line)
        lm = LEVEL_RE.search(line)
        if lm:
            per_user_levels[u][lm.group(1)] += 1
        matched_seed = False
        for name, cat, rx in RULES:
            if rx.search(line):
                # specialize VERDICT/FAIL
                if name == 'VERDICT_FAIL':
                    m = rx.search(line)
                    sig = 'VERDICT:' + m.group(1)
                elif name == 'FAIL_TOKEN':
                    m = rx.search(line)
                    sig = 'FAIL:' + m.group(1)
                elif name == 'PROXY_HEALTH':
                    # keep both PROXY_HEALTH and ok=0 variant via separate rules
                    sig = name
                    if 'ok=0' in line:
                        add('PROXY_HEALTH_ok0', 'proxy', u, line, ts)
                else:
                    sig = name
                add(sig, cat, u, line, ts)
                matched_seed = True
        # Any ERROR/WARN that didn't match a seed still gets a generic signature
        if lm and lm.group(1) in ('ERROR','WARN','WARNING') and not matched_seed:
            sig, cat = generic_sig(line)
            add(sig, cat, u, line, ts)

# laptop-exec logs — different format; capture timeouts/denies/errors
LE_RULES = [
    ("LE_timeout", "multiagent", re.compile(r'timeout|timed out', re.I)),
    ("LE_deny", "multiagent", re.compile(r'\bDENY\b|blocked|SSH-first', re.I)),
    ("LE_slots_full", "multiagent", re.compile(r'slots full|session slots', re.I)),
    ("LE_error", "multiagent", re.compile(r'\bERROR\b|\bfail(ed)?\b', re.I)),
    ("LE_rg_rejected", "multiagent", re.compile(r'rg flag not supported|flag not supported', re.I)),
]
for path in sorted(glob.glob('/home/*/.claude/logs/laptop-exec-20260722.log')):
    u = path.split('/')[2]
    files_seen.append(('laptop-exec', u, path, os.path.getsize(path)))
    for line in open(path, errors='replace'):
        ts = extract_ts(line)
        for name, cat, rx in LE_RULES:
            if rx.search(line):
                add(name, cat, u, line, ts)

print('FILES:')
for kind,u,p,sz in files_seen:
    print(f'  {kind} user={u} bytes={sz} path={p}')

print('LEVEL_COUNTS_BY_USER:')
for u in sorted(per_user_levels):
    parts = ' '.join(f'{k}={v}' for k,v in sorted(per_user_levels[u].items()))
    print(f'  {u}: {parts}')

# Rank by (user_count desc, count desc)
ranked = sorted(hits.items(), key=lambda kv: (-len(kv[1].users), -kv[1].count, kv[0]))
print('SIGNATURES:')
for sig, h in ranked:
    users = ','.join(sorted(h.users))
    cat = cats.get(sig, '?')
    # Priority heuristic
    p0 = {'LOG_SYNC_FAIL','PROXY_HEALTH_ok0','machineid_file_mismatch','UPDATE_swap_fail','SESSION_STATUS_BROKEN','AUTH_ERROR','SIDECAR_ENSURE','slots_full','Connection_refused','claude-mount_fail'}
    p1 = {'PROXY_HEALTH','CURSOR_PROXY_CLEAR','OUTDATED_SCRIPTS','UPDATE_UNHANDLED','TUNNEL_DROP','foreign_peer','SSHFS_NOT_MOUNTED','need_mount','LE_timeout','LE_slots_full','sshd_auth_fail','PUSH_CONF_blocked'}
    if sig in p0 or sig.startswith('VERDICT:') or sig.startswith('AUTH:') or sig.startswith('FAIL:'):
        pri = 'P0'
    elif sig in p1 or sig.startswith('GEN:ERROR:'):
        pri = 'P1'
    else:
        pri = 'P2'
    print(f'---')
    print(f'SIG={sig}')
    print(f'PRI={pri}')
    print(f'CAT={cat}')
    print(f'USERS={users}')
    print(f'COUNT={h.count}')
    print(f'FIRST={h.first}')
    print(f'LAST={h.last}')
    print(f'EXAMPLE={h.example}')

print('===TOP_RAW_ERROR_WARN_SAMPLES===')
# dump up to 3 ERROR and 3 WARN lines per user for human review
for path in sorted(glob.glob('/home/*/.claude/logs/connect-20260722.log')):
    u = path.split('/')[2]
    errs, warns = [], []
    for line in open(path, errors='replace'):
        if '[ERROR]' in line and len(errs) < 5:
            errs.append(line.rstrip()[:240])
        elif '[WARN]' in line and len(warns) < 5:
            warns.append(line.rstrip()[:240])
    print(f'USER={u} err_samples={len(errs)} warn_samples={len(warns)}')
    for e in errs:
        print('  E|'+e)
    for w in warns:
        print('  W|'+w)

print('===LE_TAIL_PER_USER===')
for path in sorted(glob.glob('/home/*/.claude/logs/laptop-exec-20260722.log')):
    u = path.split('/')[2]
    lines = open(path, errors='replace').read().splitlines()
    print(f'USER={u} lines={len(lines)}')
    for L in lines[-8:]:
        print('  '+L[:220])

print('===DONE_INVENTORY===')
PY

echo __DONE__
'@

[IO.File]::WriteAllText($localSh, $script.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
& scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -o ControlPath=none -q $localSh "${target}:${remoteSh}"
if ($LASTEXITCODE -ne 0) { throw "scp failed exit=$LASTEXITCODE" }

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh.exe'
$psi.Arguments = "-o BatchMode=yes -o ConnectTimeout=25 -o ControlMaster=no -o ControlPath=none $target `"sudo -S -p '' bash $remoteSh; rm -f $remoteSh`""
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine($pw)
$p.StandardInput.Close()
if (-not $p.WaitForExit(180000)) {
  try { $p.Kill() } catch {}
  throw 'ssh/sudo inventory timeout 180s'
}
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
Write-Output $out
foreach ($line in ($err -split "`n")) {
  if ($line -and ($line -notmatch '(?i)password')) { Write-Output ("ERR: " + $line) }
}
if ($out -notmatch '__DONE__') { throw ("no __DONE__ exit=" + $p.ExitCode) }
Remove-Item -Force $localSh -EA SilentlyContinue
