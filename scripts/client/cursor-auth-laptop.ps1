# cursor-auth-laptop.ps1 — sync golden Cursor auth server -> laptop (Remote SSH chat uses local tokens)
# Requires: SshX, Get-CursorRemoteProfileDir (editor-launch.ps1); $Alias at call time
#
# Never closes any Cursor window (personal or server-profile). Auth keys are merged
# into the open state.vscdb via SQLite UPSERT so many windows can share one profile.

function Invoke-CursorAuthPython {
    param([Parameter(Mandatory)][string]$Script)
    $Script | python - 2>$null | Out-Null
    return $LASTEXITCODE
}

function Invoke-CursorAuthPythonOutput {
    param([Parameter(Mandatory)][string]$Script)
    return ($Script | python - 2>$null)
}

function Get-LocalCursorGlobalStorage {
    $root = Join-Path (Get-CursorRemoteProfileDir) 'User\globalStorage'
    if (-not (Test-Path $root)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    return $root
}

function Get-RemoteCursorAuthFromGolden {
    param([Parameter(Mandatory)][string]$Alias)

    $line = (SshX 'python3 /usr/local/lib/claude-server/cursor-auth-lib.py laptop-auth-json 2>/dev/null' 2>$null |
        Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
    if ($line) {
        try {
            $obj = $line.Trim() | ConvertFrom-Json
            if ($obj.'cursorAuth/accessToken' -and $obj.'cursorAuth/refreshToken') { return $obj }
        } catch { }
    }

    # SCP golden bundle and build payload locally (avoids ssh quoting; works before server lib deploy).
    $tmp = Join-Path $env:TEMP ("cursor-golden-{0}" -f [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $ok = $true
        foreach ($pair in @(
            @{ Remote = '/etc/cursor-auth/golden/auth.json'; Local = 'auth.json' },
            @{ Remote = '/etc/cursor-auth/golden/state-keys.json'; Local = 'state-keys.json' },
            @{ Remote = '/etc/cursor-auth/golden/machine-id.txt'; Local = 'machine-id.txt' }
        )) {
            $dst = Join-Path $tmp $pair.Local
            scp -o BatchMode=yes -o ConnectTimeout=20 -q "${Alias}:$($pair.Remote)" $dst 2>$null
            if ($pair.Local -eq 'auth.json' -and $LASTEXITCODE -ne 0) { $ok = $false }
        }
        if (-not $ok) { return $null }

        $prevDir = $env:_CURSOR_GOLDEN_DIR
        $env:_CURSOR_GOLDEN_DIR = $tmp
        $parsed = $null
        try {
            $jsonLine = Invoke-CursorAuthPythonOutput @'
import json, os, sys
g = os.environ['_CURSOR_GOLDEN_DIR']
auth_path = os.path.join(g, 'auth.json')
try:
    with open(auth_path, encoding='utf-8') as f:
        auth = json.load(f)
except (json.JSONDecodeError, OSError):
    sys.exit(1)
vals = {}
if auth.get('accessToken'):
    vals['cursorAuth/accessToken'] = auth['accessToken']
if auth.get('refreshToken'):
    vals['cursorAuth/refreshToken'] = auth['refreshToken']
if auth.get('cachedEmail'):
    vals['cursorAuth/cachedEmail'] = auth['cachedEmail']
if auth.get('cachedSignUpType'):
    vals['cursorAuth/cachedSignUpType'] = auth['cachedSignUpType']
if auth.get('stripeMembershipType'):
    vals['cursorAuth/stripeMembershipType'] = auth['stripeMembershipType']
if auth.get('stripeSubscriptionStatus'):
    vals['cursorAuth/stripeSubscriptionStatus'] = auth['stripeSubscriptionStatus']
sk = os.path.join(g, 'state-keys.json')
if os.path.isfile(sk):
    try:
        with open(sk, encoding='utf-8') as f:
            extra = json.load(f)
        if isinstance(extra, dict):
            vals.update({str(k): str(v) for k, v in extra.items() if v})
    except (json.JSONDecodeError, OSError):
        pass
mid_path = os.path.join(g, 'machine-id.txt')
if os.path.isfile(mid_path):
    mid = open(mid_path, encoding='utf-8').read().strip()
    if mid:
        vals['storage.serviceMachineId'] = mid
        for k in ('telemetry.machineId', 'telemetry.macMachineId',
                  'telemetry.devDeviceId', 'telemetry.sqmId'):
            vals.setdefault(k, mid)
if vals.get('cursorAuth/accessToken') and vals.get('cursorAuth/refreshToken'):
    print(json.dumps(vals))
'@ | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
            if ($jsonLine) {
                $parsed = $jsonLine.Trim() | ConvertFrom-Json
            }
        } finally {
            if ($null -eq $prevDir) { Remove-Item Env:\_CURSOR_GOLDEN_DIR -ErrorAction SilentlyContinue }
            else { $env:_CURSOR_GOLDEN_DIR = $prevDir }
        }
        if ($parsed.'cursorAuth/accessToken' -and $parsed.'cursorAuth/refreshToken') {
            return $parsed
        }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Merge-CursorAuthIntoLocalDb {
    param(
        [Parameter(Mandatory)][string]$DbPath,
        [Parameter(Mandatory)]$AuthValues
    )
    $map = @{}
    foreach ($prop in $AuthValues.PSObject.Properties) {
        if ($prop.Value) { $map[$prop.Name] = [string]$prop.Value }
    }
    if ($map.Count -eq 0) { return $false }
    $json = ($map | ConvertTo-Json -Compress)
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $prevDb = $env:_CURSOR_AUTH_DB
        $prevJson = $env:_CURSOR_AUTH_VALUES
        $env:_CURSOR_AUTH_DB = $DbPath
        $env:_CURSOR_AUTH_VALUES = $json
        try {
            $code = Invoke-CursorAuthPython @'
import json, os, sqlite3, sys
db = os.environ['_CURSOR_AUTH_DB']
vals = json.loads(os.environ['_CURSOR_AUTH_VALUES'])
conn = sqlite3.connect(db, timeout=30)
conn.execute("PRAGMA busy_timeout=30000")
try:
    conn.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
    for k, v in vals.items():
        if v:
            conn.execute(
                "INSERT INTO ItemTable (key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (k, v),
            )
    conn.commit()
    conn.execute("PRAGMA wal_checkpoint(FULL)")
except sqlite3.Error:
    sys.exit(1)
finally:
    conn.close()
'@
            if ($code -eq 0) { return $true }
        } finally {
            if ($null -eq $prevDb) { Remove-Item Env:\_CURSOR_AUTH_DB -ErrorAction SilentlyContinue }
            else { $env:_CURSOR_AUTH_DB = $prevDb }
            if ($null -eq $prevJson) { Remove-Item Env:\_CURSOR_AUTH_VALUES -ErrorAction SilentlyContinue }
            else { $env:_CURSOR_AUTH_VALUES = $prevJson }
        }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Merge-CursorStorageJsonFromGolden {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$LocalPath
    )
    $tmp = "$LocalPath.merge-src"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "${Alias}:/etc/cursor-auth/golden/storage.json" $tmp 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $prevSrc = $env:_CURSOR_STORAGE_SRC
    $prevDst = $env:_CURSOR_STORAGE_DST
    $env:_CURSOR_STORAGE_SRC = $tmp
    $env:_CURSOR_STORAGE_DST = $LocalPath
    try {
        $code = Invoke-CursorAuthPython @'
import json, os, sys
src = os.environ['_CURSOR_STORAGE_SRC']
dst = os.environ['_CURSOR_STORAGE_DST']
keys = [
    'telemetry.machineId', 'telemetry.macMachineId',
    'telemetry.devDeviceId', 'telemetry.sqmId',
]
try:
    with open(src, encoding='utf-8') as f:
        remote = json.load(f)
except (json.JSONDecodeError, OSError):
    sys.exit(1)
local = {}
if os.path.isfile(dst):
    try:
        with open(dst, encoding='utf-8') as f:
            data = json.load(f)
        if isinstance(data, dict):
            local = data
    except (json.JSONDecodeError, OSError):
        pass
for k in keys:
    if k in remote and remote[k]:
        local[k] = remote[k]
out = json.dumps(local, indent=2) + '\n'
tmp = dst + '.merge-tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(out)
os.replace(tmp, dst)
'@
        return ($code -eq 0)
    } catch {
        return $false
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($null -eq $prevSrc) { Remove-Item Env:\_CURSOR_STORAGE_SRC -ErrorAction SilentlyContinue }
        else { $env:_CURSOR_STORAGE_SRC = $prevSrc }
        if ($null -eq $prevDst) { Remove-Item Env:\_CURSOR_STORAGE_DST -ErrorAction SilentlyContinue }
        else { $env:_CURSOR_STORAGE_DST = $prevDst }
    }
}

function Test-LocalCursorAuthDb {
    param([Parameter(Mandatory)][string]$DbPath)
    if (-not (Test-Path $DbPath)) { return $false }
    $prev = $env:_CURSOR_AUTH_DB
    $env:_CURSOR_AUTH_DB = $DbPath
    try {
        $code = Invoke-CursorAuthPython @'
import os, sqlite3, sys
p = os.environ.get('_CURSOR_AUTH_DB', '')
c = sqlite3.connect(p)
ok = (
    c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1").fetchone()
    and c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/refreshToken' LIMIT 1").fetchone()
)
c.close()
sys.exit(0 if ok else 1)
'@
        return ($code -eq 0)
    } catch {
        return $false
    } finally {
        if ($null -eq $prev) { Remove-Item Env:\_CURSOR_AUTH_DB -ErrorAction SilentlyContinue }
        else { $env:_CURSOR_AUTH_DB = $prev }
    }
}

function Test-LocalCursorAuthComplete {
    param([Parameter(Mandatory)][string]$DbPath)
    if (-not (Test-Path $DbPath)) { return $false }
    $prev = $env:_CURSOR_AUTH_DB
    $env:_CURSOR_AUTH_DB = $DbPath
    try {
        $code = Invoke-CursorAuthPython @'
import os, sqlite3, sys
p = os.environ.get('_CURSOR_AUTH_DB', '')
c = sqlite3.connect(p)
def ln(key):
    row = c.execute("SELECT length(value) FROM ItemTable WHERE key=? LIMIT 1", (key,)).fetchone()
    return int(row[0]) if row and row[0] else 0
ok = (
    ln('cursorAuth/accessToken') > 0
    and ln('cursorAuth/refreshToken') > 0
    and ln('cursorAuth/cachedEmail') > 0
    and ln('cursorAuth/stripeMembershipType') > 0
)
c.close()
sys.exit(0 if ok else 1)
'@
        return ($code -eq 0)
    } catch {
        return $false
    } finally {
        if ($null -eq $prev) { Remove-Item Env:\_CURSOR_AUTH_DB -ErrorAction SilentlyContinue }
        else { $env:_CURSOR_AUTH_DB = $prev }
    }
}

function Read-LocalServerProfileAuthBundle {
    $gs = Get-LocalCursorGlobalStorage
    $dbPath = Join-Path $gs 'state.vscdb'
    if (-not (Test-Path $dbPath)) { return $null }
    $prev = $env:_CURSOR_AUTH_DB
    $env:_CURSOR_AUTH_DB = $dbPath
    try {
        $line = Invoke-CursorAuthPythonOutput @'
import json, os, sqlite3
db = os.environ['_CURSOR_AUTH_DB']
c = sqlite3.connect(db)
rows = c.execute("""
    SELECT key, value FROM ItemTable
    WHERE key LIKE 'cursorAuth/%'
       OR key LIKE 'telemetry.%'
       OR key = 'storage.serviceMachineId'
""").fetchall()
c.close()
vals = {str(k): str(v) for k, v in rows if k and v}
print(json.dumps(vals))
'@ | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
        if (-not $line) { return $null }
        return ($line.Trim() | ConvertFrom-Json)
    } catch {
        return $null
    } finally {
        if ($null -eq $prev) { Remove-Item Env:\_CURSOR_AUTH_DB -ErrorAction SilentlyContinue }
        else { $env:_CURSOR_AUTH_DB = $prev }
    }
}

function Push-CursorGoldenFromServerProfile {
    param([Parameter(Mandatory)][string]$Alias)

    $gs = Get-LocalCursorGlobalStorage
    $dbPath = Join-Path $gs 'state.vscdb'
    if (-not (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
        return [PSCustomObject]@{
            Ok      = $false
            Message = 'Sign in to the SERVER Cursor account in [Claude Server] first (never your personal account).'
        }
    }

    $stateValues = Read-LocalServerProfileAuthBundle
    if (-not $stateValues) {
        return [PSCustomObject]@{ Ok = $false; Message = 'Could not read server profile auth.' }
    }

    $authPayload = @{
        accessToken            = [string]$stateValues.'cursorAuth/accessToken'
        refreshToken           = [string]$stateValues.'cursorAuth/refreshToken'
        cachedEmail            = [string]$stateValues.'cursorAuth/cachedEmail'
        cachedSignUpType       = [string]$stateValues.'cursorAuth/cachedSignUpType'
        stripeMembershipType   = [string]$stateValues.'cursorAuth/stripeMembershipType'
        stripeSubscriptionStatus = [string]$stateValues.'cursorAuth/stripeSubscriptionStatus'
    }

    $localTmp = Join-Path $env:TEMP ("cursor-laptop-golden-{0}" -f [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $localTmp | Out-Null
    $remoteDir = "/tmp/cursor-laptop-golden-$($env:USERNAME.ToLower())"

    try {
        ($authPayload | ConvertTo-Json) | Set-Content -Path (Join-Path $localTmp 'auth.json') -Encoding UTF8
        ($stateValues | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $localTmp 'state-keys.json') -Encoding UTF8
        $storageSrc = Join-Path $gs 'storage.json'
        if (Test-Path $storageSrc) {
            Copy-Item $storageSrc (Join-Path $localTmp 'storage.json') -Force
        }

        SshX "rm -rf '$remoteDir' && mkdir -p '$remoteDir'" 2>$null | Out-Null
        scp -o BatchMode=yes -o ConnectTimeout=30 -q "$localTmp\auth.json" "${Alias}:${remoteDir}/auth.json" 2>$null
        if ($LASTEXITCODE -ne 0) { return [PSCustomObject]@{ Ok = $false; Message = 'SCP auth.json failed.' } }
        scp -o BatchMode=yes -o ConnectTimeout=30 -q "$localTmp\state-keys.json" "${Alias}:${remoteDir}/state-keys.json" 2>$null
        if ($LASTEXITCODE -ne 0) { return [PSCustomObject]@{ Ok = $false; Message = 'SCP state-keys.json failed.' } }
        if (Test-Path (Join-Path $localTmp 'storage.json')) {
            scp -o BatchMode=yes -o ConnectTimeout=30 -q "$localTmp\storage.json" "${Alias}:${remoteDir}/storage.json" 2>$null
        }

        Write-Host ''
        Write-Host '    Importing golden on server (sudo password may be required)...' -ForegroundColor Cyan
        ssh -t -o BatchMode=yes -o ConnectTimeout=30 $Alias "sudo claude-server import-cursor-golden-laptop '$remoteDir'"
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Ok = $false; Message = 'Server import failed.' }
        }

        $null = Sync-CursorGoldenAuth -Alias $Alias
        return [PSCustomObject]@{
            Ok      = (Test-LocalCursorAuthComplete -DbPath $dbPath)
            Message = 'Golden pushed from [Claude Server] profile. Reload Window in Cursor.'
        }
    } finally {
        Remove-Item $localTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}


function Sync-CursorGoldenAuth {
    param(
        [Parameter(Mandatory)][string]$Alias
    )

    $skipped = [PSCustomObject]@{ Ok = $false; Skipped = $true }

    $probe = (SshX "test -f /etc/cursor-auth/golden/auth.json && echo yes" 2>$null) -join ''
    if ($probe -notmatch 'yes') { return $skipped }

    SshX "cursor-auth-sync --force 2>&1" 2>$null | Out-Null

    $localGs = Get-LocalCursorGlobalStorage
    $dbPath = Join-Path $localGs 'state.vscdb'
    $storagePath = Join-Path $localGs 'storage.json'

    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias
    if (-not $authValues) { return $skipped }

    $merged = Merge-CursorAuthIntoLocalDb -DbPath $dbPath -AuthValues $authValues
    if (-not $merged) {
        return [PSCustomObject]@{ Ok = $false; Skipped = $false }
    }

    $null = Merge-CursorStorageJsonFromGolden -Alias $Alias -LocalPath $storagePath

    $complete = Test-LocalCursorAuthComplete -DbPath $dbPath
    $tokens = Test-LocalCursorAuthDb -DbPath $dbPath
    return [PSCustomObject]@{
        Ok            = $complete
        TokensOnly    = ($tokens -and -not $complete)
        Skipped       = $false
    }
}
