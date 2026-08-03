# cursor-auth-laptop.ps1 - sync golden Cursor auth server -> laptop (Remote SSH chat uses local tokens)
# Requires: SshX, Get-CursorRemoteProfileDir (editor-launch.ps1); $Alias at call time
#
# Never closes any Cursor window (personal or server-profile). Auth keys are merged
# into the open state.vscdb via SQLite UPSERT so many windows can share one profile.
# SQLite via Windows winsqlite3.dll (fallback sqlite3.dll) - no Python dependency.

function Write-AuthSyncLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'DEBUG'
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "AUTH: $Message" $Level
    }
}

$script:CursorAuthSqliteReady = $false
$script:CursorStorageJsonKeys = @(
    'telemetry.machineId',
    'telemetry.macMachineId',
    'telemetry.devDeviceId',
    'telemetry.sqmId'
)

function Initialize-CursorAuthSqlite {
    if ($script:CursorAuthSqliteReady) { return $true }
    if (-not $script:CursorAuthSqliteTypeAdded) {
        $csharp = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CursorAuthSqlite
{
    private const int SQLITE_OK = 0;
    private const int SQLITE_ROW = 100;
    private const int SQLITE_DONE = 101;
    private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_open(IntPtr filename, out IntPtr db);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_close(IntPtr db);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_busy_timeout(IntPtr db, int ms);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_prepare_v2(IntPtr db, string sql, int nbytes, out IntPtr stmt, out IntPtr tail);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_bind_text(IntPtr stmt, int index, byte[] text, int nbytes, IntPtr destructor);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_step(IntPtr stmt);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_finalize(IntPtr stmt);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int sqlite3_column_int(IntPtr stmt, int iCol);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr sqlite3_column_text(IntPtr stmt, int iCol);

    private static IntPtr _module = IntPtr.Zero;
    private static bool _ready;
    private static sqlite3_open _open;
    private static sqlite3_close _close;
    private static sqlite3_busy_timeout _busyTimeout;
    private static sqlite3_prepare_v2 _prepare;
    private static sqlite3_bind_text _bindText;
    private static sqlite3_step _step;
    private static sqlite3_finalize _finalize;
    private static sqlite3_column_int _columnInt;
    private static sqlite3_column_text _columnText;

    private static T GetDelegate<T>(string name) where T : class
    {
        IntPtr addr = GetProcAddress(_module, name);
        if (addr == IntPtr.Zero) { return null; }
        return Marshal.GetDelegateForFunctionPointer(addr, typeof(T)) as T;
    }

    public static bool EnsureLoaded()
    {
        if (_ready) { return true; }
        foreach (string dll in new[] { "winsqlite3", "sqlite3" })
        {
            _module = LoadLibrary(dll);
            if (_module != IntPtr.Zero) { break; }
        }
        if (_module == IntPtr.Zero) { return false; }

        _open = GetDelegate<sqlite3_open>("sqlite3_open");
        _close = GetDelegate<sqlite3_close>("sqlite3_close");
        _busyTimeout = GetDelegate<sqlite3_busy_timeout>("sqlite3_busy_timeout");
        _prepare = GetDelegate<sqlite3_prepare_v2>("sqlite3_prepare_v2");
        _bindText = GetDelegate<sqlite3_bind_text>("sqlite3_bind_text");
        _step = GetDelegate<sqlite3_step>("sqlite3_step");
        _finalize = GetDelegate<sqlite3_finalize>("sqlite3_finalize");
        _columnInt = GetDelegate<sqlite3_column_int>("sqlite3_column_int");
        _columnText = GetDelegate<sqlite3_column_text>("sqlite3_column_text");

        if (_open == null || _close == null || _prepare == null || _bindText == null ||
            _step == null || _finalize == null || _busyTimeout == null || _columnInt == null ||
            _columnText == null)
        {
            return false;
        }
        _ready = true;
        return true;
    }

    private static bool OpenDb(string dbPath, int busyMs, out IntPtr db)
    {
        db = IntPtr.Zero;
        if (!EnsureLoaded()) { return false; }
        byte[] pathBytes = Encoding.UTF8.GetBytes(dbPath + "\0");
        GCHandle handle = GCHandle.Alloc(pathBytes, GCHandleType.Pinned);
        try
        {
            if (_open(handle.AddrOfPinnedObject(), out db) != SQLITE_OK) { return false; }
            _busyTimeout(db, busyMs);
            return true;
        }
        finally
        {
            handle.Free();
        }
    }

    private static bool ExecStatement(IntPtr db, string sql, params string[] binds)
    {
        IntPtr stmt = IntPtr.Zero;
        try
        {
            IntPtr tail;
            if (_prepare(db, sql, -1, out stmt, out tail) != SQLITE_OK) { return false; }
            for (int i = 0; i < binds.Length; i++)
            {
                string val = binds[i] ?? string.Empty;
                byte[] bytes = Encoding.UTF8.GetBytes(val);
                if (_bindText(stmt, i + 1, bytes, bytes.Length, SQLITE_TRANSIENT) != SQLITE_OK) { return false; }
            }
            int rc = _step(stmt);
            return rc == SQLITE_DONE;
        }
        finally
        {
            if (stmt != IntPtr.Zero) { _finalize(stmt); }
        }
    }

    private static bool HasKey(IntPtr db, string key)
    {
        IntPtr stmt = IntPtr.Zero;
        try
        {
            string sql = "SELECT 1 FROM ItemTable WHERE key=? LIMIT 1";
            IntPtr tail;
            if (_prepare(db, sql, -1, out stmt, out tail) != SQLITE_OK) { return false; }
            byte[] keyBytes = Encoding.UTF8.GetBytes(key);
            if (_bindText(stmt, 1, keyBytes, keyBytes.Length, SQLITE_TRANSIENT) != SQLITE_OK) { return false; }
            return _step(stmt) == SQLITE_ROW;
        }
        finally
        {
            if (stmt != IntPtr.Zero) { _finalize(stmt); }
        }
    }

    private static int ValueLength(IntPtr db, string key)
    {
        IntPtr stmt = IntPtr.Zero;
        try
        {
            string sql = "SELECT length(value) FROM ItemTable WHERE key=? LIMIT 1";
            IntPtr tail;
            if (_prepare(db, sql, -1, out stmt, out tail) != SQLITE_OK) { return 0; }
            byte[] keyBytes = Encoding.UTF8.GetBytes(key);
            if (_bindText(stmt, 1, keyBytes, keyBytes.Length, SQLITE_TRANSIENT) != SQLITE_OK) { return 0; }
            if (_step(stmt) != SQLITE_ROW) { return 0; }
            return _columnInt(stmt, 0);
        }
        finally
        {
            if (stmt != IntPtr.Zero) { _finalize(stmt); }
        }
    }

    private static string PtrToUtf8String(IntPtr ptr)
    {
        // Marshal.PtrToStringUTF8 is not available on the .NET Framework that
        // powershell.exe (5.1) hosts Add-Type against - decode manually instead.
        if (ptr == IntPtr.Zero) { return null; }
        int len = 0;
        while (Marshal.ReadByte(ptr, len) != 0) { len++; }
        if (len == 0) { return string.Empty; }
        byte[] buffer = new byte[len];
        Marshal.Copy(ptr, buffer, 0, len);
        return Encoding.UTF8.GetString(buffer);
    }

    private static string GetValue(IntPtr db, string key)
    {
        IntPtr stmt = IntPtr.Zero;
        try
        {
            string sql = "SELECT value FROM ItemTable WHERE key=? LIMIT 1";
            IntPtr tail;
            if (_prepare(db, sql, -1, out stmt, out tail) != SQLITE_OK) { return null; }
            byte[] keyBytes = Encoding.UTF8.GetBytes(key);
            if (_bindText(stmt, 1, keyBytes, keyBytes.Length, SQLITE_TRANSIENT) != SQLITE_OK) { return null; }
            if (_step(stmt) != SQLITE_ROW) { return null; }
            return PtrToUtf8String(_columnText(stmt, 0));
        }
        finally
        {
            if (stmt != IntPtr.Zero) { _finalize(stmt); }
        }
    }

    // Public single-key read (opens its own short-lived session).
    public static string GetValue(string dbPath, string key)
    {
        IntPtr db;
        if (!OpenDb(dbPath, 5000, out db)) { return null; }
        try
        {
            return GetValue(db, key);
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }

    public static bool MergeAuthValues(string dbPath, IDictionary<string, string> values)
    {
        if (values == null || values.Count == 0) { return false; }
        IntPtr db;
        if (!OpenDb(dbPath, 30000, out db)) { return false; }
        try
        {
            if (!ExecStatement(db,
                "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)"))
            {
                return false;
            }
            foreach (KeyValuePair<string, string> pair in values)
            {
                if (string.IsNullOrEmpty(pair.Key) || string.IsNullOrEmpty(pair.Value)) { continue; }
                if (!ExecStatement(db,
                    "INSERT INTO ItemTable (key, value) VALUES (?, ?) " +
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    pair.Key, pair.Value))
                {
                    return false;
                }
            }
            return true;
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }

    public static bool DeleteKeys(string dbPath, string[] keys)
    {
        if (keys == null || keys.Length == 0) { return true; }
        IntPtr db;
        if (!OpenDb(dbPath, 30000, out db)) { return false; }
        try
        {
            foreach (string key in keys)
            {
                if (string.IsNullOrEmpty(key)) { continue; }
                if (!ExecStatement(db, "DELETE FROM ItemTable WHERE key = ?", key))
                {
                    return false;
                }
            }
            return true;
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }

    public static bool HasAuthTokens(string dbPath)
    {
        IntPtr db;
        if (!OpenDb(dbPath, 5000, out db)) { return false; }
        try
        {
            return HasKey(db, "cursorAuth/accessToken") && HasKey(db, "cursorAuth/refreshToken");
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }

    public static bool IsAuthComplete(string dbPath)
    {
        IntPtr db;
        if (!OpenDb(dbPath, 5000, out db)) { return false; }
        try
        {
            return ValueLength(db, "cursorAuth/accessToken") > 0
                && ValueLength(db, "cursorAuth/refreshToken") > 0
                && ValueLength(db, "cursorAuth/cachedEmail") > 0
                && ValueLength(db, "cursorAuth/stripeMembershipType") > 0
                && ValueLength(db, "storage.serviceMachineId") > 0;
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }

    // Single OpenDb session for both the completeness gate and the serviceMachineId
    // read used to heal Electron's machineid file - avoids opening the DB twice.
    public static bool TryGetAuthState(string dbPath, out bool complete, out string serviceMachineId)
    {
        complete = false;
        serviceMachineId = null;
        IntPtr db;
        if (!OpenDb(dbPath, 5000, out db)) { return false; }
        try
        {
            bool tokensComplete = ValueLength(db, "cursorAuth/accessToken") > 0
                && ValueLength(db, "cursorAuth/refreshToken") > 0
                && ValueLength(db, "cursorAuth/cachedEmail") > 0
                && ValueLength(db, "cursorAuth/stripeMembershipType") > 0;
            serviceMachineId = GetValue(db, "storage.serviceMachineId");
            complete = tokensComplete && !string.IsNullOrEmpty(serviceMachineId);
            return true;
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }

    public static bool HasNonEmptyValue(string dbPath, string key)
    {
        IntPtr db;
        if (!OpenDb(dbPath, 5000, out db)) { return false; }
        try
        {
            return ValueLength(db, key) > 0;
        }
        finally
        {
            if (db != IntPtr.Zero) { _close(db); }
        }
    }
}
'@
        $prevGuard = $env:ECC_GATEGUARD
        $env:ECC_GATEGUARD = 'off'
        try {
            Add-Type -TypeDefinition $csharp -ErrorAction Stop
            $script:CursorAuthSqliteTypeAdded = $true
        } catch {
            return $false
        } finally {
            if ($null -eq $prevGuard) { Remove-Item Env:\ECC_GATEGUARD -ErrorAction SilentlyContinue }
            else { $env:ECC_GATEGUARD = $prevGuard }
        }
    }
    if ([CursorAuthSqlite]::EnsureLoaded()) {
        $script:CursorAuthSqliteReady = $true
        return $true
    }
    return $false
}

function Get-LocalCursorGlobalStorage {
    $root = Join-Path (Get-CursorRemoteProfileDir) 'User\globalStorage'
    if (-not (Test-Path $root)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
    }
    return $root
}

function Build-CursorAuthValuesFromGoldenDir {
    param([Parameter(Mandatory)][string]$GoldenDir)

    $vals = @{}
    $auth = $null
    $authPath = Join-Path $GoldenDir 'auth.json'
    if (Test-Path $authPath) {
        try { $auth = Get-Content $authPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $skPath = Join-Path $GoldenDir 'state-keys.json'
    if (Test-Path $skPath) {
        try {
            $extra = Get-Content $skPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($extra) {
                foreach ($prop in $extra.PSObject.Properties) {
                    if ($prop.Value) { $vals[$prop.Name] = [string]$prop.Value }
                }
            }
        } catch { }
    }

    $machineId = ''
    $midPath = Join-Path $GoldenDir 'machine-id.txt'
    if (Test-Path $midPath) {
        $machineId = (Get-Content $midPath -Raw -Encoding UTF8).Trim()
    }

    if ($vals.Count -gt 0) {
        if ($auth) {
            if ($auth.accessToken) { $vals['cursorAuth/accessToken'] = [string]$auth.accessToken }
            if ($auth.refreshToken) { $vals['cursorAuth/refreshToken'] = [string]$auth.refreshToken }
            # Keep auth.json metadata on early (state-keys present) path - same as full path.
            if ($auth.cachedEmail) { $vals['cursorAuth/cachedEmail'] = [string]$auth.cachedEmail }
            if ($auth.cachedSignUpType) { $vals['cursorAuth/cachedSignUpType'] = [string]$auth.cachedSignUpType }
            if ($auth.stripeMembershipType) { $vals['cursorAuth/stripeMembershipType'] = [string]$auth.stripeMembershipType }
            if ($auth.stripeSubscriptionStatus) { $vals['cursorAuth/stripeSubscriptionStatus'] = [string]$auth.stripeSubscriptionStatus }
        }
        if ($machineId) {
            $vals['storage.serviceMachineId'] = $machineId
            foreach ($k in $script:CursorStorageJsonKeys) {
                if (-not $vals.ContainsKey($k)) { $vals[$k] = $machineId }
            }
        }
        if ($vals['cursorAuth/accessToken'] -and $vals['cursorAuth/refreshToken']) {
            return [PSCustomObject]$vals
        }
        return $null
    }

    if ($auth) {
        if ($auth.accessToken) { $vals['cursorAuth/accessToken'] = [string]$auth.accessToken }
        if ($auth.refreshToken) { $vals['cursorAuth/refreshToken'] = [string]$auth.refreshToken }
        if ($auth.cachedEmail) { $vals['cursorAuth/cachedEmail'] = [string]$auth.cachedEmail }
        if ($auth.cachedSignUpType) { $vals['cursorAuth/cachedSignUpType'] = [string]$auth.cachedSignUpType }
        if ($auth.stripeMembershipType) { $vals['cursorAuth/stripeMembershipType'] = [string]$auth.stripeMembershipType }
        if ($auth.stripeSubscriptionStatus) { $vals['cursorAuth/stripeSubscriptionStatus'] = [string]$auth.stripeSubscriptionStatus }
    }
    if ($machineId) {
        $vals['storage.serviceMachineId'] = $machineId
        foreach ($k in $script:CursorStorageJsonKeys) {
            if (-not $vals.ContainsKey($k)) { $vals[$k] = $machineId }
        }
    }

    if ($vals['cursorAuth/accessToken'] -and $vals['cursorAuth/refreshToken']) {
        return [PSCustomObject]$vals
    }
    return $null
}

function Get-CursorAuthTempRoot {
    # Prefer a resolvable long path; broken 8.3 TEMP shorts (C:\Users\XXXX~1.YYY) can make Remove-Item
    # throw a terminating error that connect.ps1 trap surfaces as Unexpected error on disconnect.
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
        [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'Temp'))
    }
    if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
        [void]$candidates.Add((Join-Path $env:USERPROFILE 'AppData\Local\Temp'))
    }
    try {
        $p = [System.IO.Path]::GetTempPath()
        if ($p -and ($p -notmatch '~')) { [void]$candidates.Add($p) }
    } catch {}
    if ($env:TEMP -and ($env:TEMP -notmatch '~')) { [void]$candidates.Add($env:TEMP) }
    if ($env:TMP -and ($env:TMP -notmatch '~')) { [void]$candidates.Add($env:TMP) }
    [void]$candidates.Add((Join-Path $env:SystemRoot 'Temp'))
    foreach ($cand in $candidates) {
        if (-not $cand -or ($cand -match '~')) { continue }
        try {
            if (-not (Test-Path -LiteralPath $cand)) {
                New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
            }
            $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName
            if ($full -and ($full -notmatch '~')) { return $full }
        } catch { continue }
    }
    $fallback = Join-Path $env:SystemRoot 'Temp'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return [System.IO.Path]::GetTempPath()
}

function Remove-CursorAuthTempDir {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    } catch {
        # never let temp cleanup abort connect disconnect
    }
}

function Get-RemoteCursorAuthFromGolden {
    param([Parameter(Mandatory)][string]$Alias)

    $tmp = Join-Path (Get-CursorAuthTempRoot) ("cursor-golden-{0}" -f [guid]::NewGuid().ToString('n'))
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
        return (Build-CursorAuthValuesFromGoldenDir -GoldenDir $tmp)
    } finally {
        Remove-CursorAuthTempDir -Path $tmp
    }
}


function Write-CursorProfileMachineId {
    param([string]$MachineId)
    if (-not $MachineId) { return $false }
    $profileDir = Get-CursorRemoteProfileDir
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    $mid = $MachineId.Trim()
    Set-Content -LiteralPath (Join-Path $profileDir 'machineid') -Value $mid -Encoding Ascii -NoNewline
    Set-Content -LiteralPath (Join-Path $profileDir 'machineId') -Value $mid -Encoding Ascii -NoNewline
    return $true
}

function Merge-CursorAuthIntoLocalDb {
    param(
        [Parameter(Mandatory)][string]$DbPath,
        [Parameter(Mandatory)]$AuthValues
    )
    if (-not (Initialize-CursorAuthSqlite)) { return $false }

    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    foreach ($prop in $AuthValues.PSObject.Properties) {
        if ($prop.Value) { $map[$prop.Name] = [string]$prop.Value }
    }
    if ($map.Count -eq 0) { return $false }

    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        if ([CursorAuthSqlite]::MergeAuthValues($DbPath, $map)) {
            $mid = $null
            if ($map.ContainsKey('storage.serviceMachineId')) { $mid = $map['storage.serviceMachineId'] }
            elseif ($map.ContainsKey('telemetry.machineId')) { $mid = $map['telemetry.machineId'] }
            if ($mid) { Write-CursorProfileMachineId -MachineId $mid | Out-Null }
            # Drop stale UI display-name cache so Settings does not keep showing the
            # previous account nickname after golden email rotation.
            Clear-CursorAuthDisplayNameCache -DbPath $DbPath
            return $true
        }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Clear-CursorAuthDisplayNameCache {
    param([Parameter(Mandatory)][string]$DbPath)
    if (-not (Test-Path -LiteralPath $DbPath)) { return }
    if (-not (Initialize-CursorAuthSqlite)) { return }
    try {
        [void][CursorAuthSqlite]::DeleteKeys($DbPath, @(
            'cursor.customize.userDisplayNameCache'
        ))
    } catch {
        # fail-open: auth tokens already merged
    }
}

function Merge-CursorStorageJsonFromGolden {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$LocalPath
    )
    $tmp = Join-Path (Get-CursorAuthTempRoot) ("cursor-storage-merge-{0}.json" -f [guid]::NewGuid().ToString('n'))
    Remove-CursorAuthTempDir -Path $tmp
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "${Alias}:/etc/cursor-auth/golden/storage.json" $tmp 2>$null
    if ($LASTEXITCODE -ne 0) {
        Remove-CursorAuthTempDir -Path $tmp
        return $false
    }

    try {
        $remote = $null
        try { $remote = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
        if (-not $remote) { return $false }

        $local = @{}
        if (Test-Path $LocalPath) {
            try {
                $existing = Get-Content $LocalPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($existing) {
                    foreach ($prop in $existing.PSObject.Properties) {
                        $local[$prop.Name] = $prop.Value
                    }
                }
            } catch { }
        }

        foreach ($k in $script:CursorStorageJsonKeys) {
            $rv = $remote.$k
            if ($rv) { $local[$k] = $rv }
        }

        $out = ($local | ConvertTo-Json -Depth 5) + "`n"
        $outTmp = "$LocalPath.merge-tmp"
        $prevGuard = $env:ECC_GATEGUARD
        $env:ECC_GATEGUARD = 'off'
        try {
            Set-Content -Path $outTmp -Value $out -Encoding UTF8 -NoNewline
            Move-Item -Path $outTmp -Destination $LocalPath -Force
        } finally {
            if ($null -eq $prevGuard) { Remove-Item Env:\ECC_GATEGUARD -ErrorAction SilentlyContinue }
            else { $env:ECC_GATEGUARD = $prevGuard }
        }
        return $true
    } catch {
        return $false
    } finally {
        Remove-CursorAuthTempDir -Path $tmp
    }
}

function Test-LocalCursorAuthDb {
    param([Parameter(Mandatory)][string]$DbPath)
    if (-not (Test-Path $DbPath)) { return $false }
    if (-not (Initialize-CursorAuthSqlite)) { return $false }
    try {
        return [CursorAuthSqlite]::HasAuthTokens($DbPath)
    } catch {
        return $false
    }
}

function Test-LocalCursorAuthComplete {
    param([Parameter(Mandatory)][string]$DbPath)
    if (-not (Test-Path $DbPath)) { return $false }
    if (-not (Initialize-CursorAuthSqlite)) { return $false }
    try {
        return [CursorAuthSqlite]::IsAuthComplete($DbPath)
    } catch {
        return $false
    }
}

# Reads completeness + storage.serviceMachineId in one SQLite session (single OpenDb),
# so callers that need both (skip-gate + machineid heal) don't open the DB twice.
function Get-LocalCursorAuthState {
    param([Parameter(Mandatory)][string]$DbPath)
    $result = [PSCustomObject]@{ Ok = $false; Complete = $false; ServiceMachineId = $null }
    if (-not (Test-Path $DbPath)) { return $result }
    if (-not (Initialize-CursorAuthSqlite)) { return $result }
    try {
        $complete = $false
        $mid = $null
        $ok = [CursorAuthSqlite]::TryGetAuthState($DbPath, [ref]$complete, [ref]$mid)
        return [PSCustomObject]@{ Ok = $ok; Complete = $complete; ServiceMachineId = $mid }
    } catch {
        return $result
    }
}

# Lightweight (no SSH, no scp) machineid heal from the local SQLite copy. Reuses an
# already-fetched Get-LocalCursorAuthState result when the caller has one (single session).
function Heal-CursorProfileMachineIdFromLocal {
    param(
        [Parameter(Mandatory)][string]$DbPath,
        [PSCustomObject]$KnownState
    )
    $state = $KnownState
    if (-not $state) { $state = Get-LocalCursorAuthState -DbPath $DbPath }
    if ($state -and $state.ServiceMachineId) {
        Write-CursorProfileMachineId -MachineId $state.ServiceMachineId | Out-Null
        return $true
    }
    return $false
}

# Server admin has not run cursor-auth-export yet (/etc/cursor-auth/golden/ absent) - a
# fully expected day-1 state, but every connect was still paying a full SSH round trip
# (plus 2 more inside Test-CursorAuthNeedsRefresh) to rediscover "still missing" each time.
# Cache the negative result locally with a short TTL so repeat connects skip the probe
# entirely; the TTL keeps it self-healing once the admin actually bootstraps golden auth.
$script:CursorGoldenMissingTtlMin = 3
function Test-CursorGoldenKnownMissing {
    $gs = Get-LocalCursorGlobalStorage
    $path = Join-Path $gs 'golden-missing-checked-at.txt'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $ageMin = ((Get-Date) - (Get-Item -LiteralPath $path).LastWriteTime).TotalMinutes
        return ($ageMin -ge 0 -and $ageMin -lt $script:CursorGoldenMissingTtlMin)
    } catch { return $false }
}
function Set-CursorGoldenMissingCache {
    $gs = Get-LocalCursorGlobalStorage
    try {
        if (-not (Test-Path -LiteralPath $gs)) { $null = New-Item -ItemType Directory -Force -Path $gs }
        Set-Content -LiteralPath (Join-Path $gs 'golden-missing-checked-at.txt') -Value (Get-Date -Format 'o') -Encoding UTF8
    } catch {}
}
function Clear-CursorGoldenMissingCache {
    $gs = Get-LocalCursorGlobalStorage
    Remove-Item -LiteralPath (Join-Path $gs 'golden-missing-checked-at.txt') -Force -ErrorAction SilentlyContinue
}

function Get-CursorGoldenExportedAtStamp {
    param([Parameter(Mandatory)][string]$Alias)
    if (-not $script:CursorGoldenStampCache) {
        $script:CursorGoldenStampCache = @{ Stamp = ''; At = $null }
    }
    $cache = $script:CursorGoldenStampCache
    if ($cache.At -and $cache.Stamp -and ((Get-Date) - $cache.At).TotalMinutes -lt 45) {
        return [string]$cache.Stamp
    }
    if (-not (Get-Command SshX -ErrorAction SilentlyContinue)) { return '' }
    $stamp = ((SshX "cat /etc/cursor-auth/golden/exported-at 2>/dev/null") -join '').Trim()
    if ($stamp) {
        $cache.Stamp = $stamp
        $cache.At = Get-Date
        # Stamp proves golden exists - never keep a stale "missing" negative cache.
        Clear-CursorGoldenMissingCache
    }
    return $stamp
}

# Stamp-first check: one SSH fetch of exported-at compared against the local
# golden-synced-at.txt stamp. When it matches (and auth is already complete),
# callers can skip the heavier Test-CursorAuthNeedsRefresh (machineid + exported-at
# re-checks -> 2 more SSH round trips) since the stamp match already proves currency.
function Test-CursorAuthStampCurrent {
    param(
        [Parameter(Mandatory)][string]$DbPath,
        [Parameter(Mandatory)][string]$Alias
    )
    $gs = Split-Path -Parent $DbPath
    $syncedAtPath = Join-Path $gs 'golden-synced-at.txt'
    $syncedAt = if (Test-Path -LiteralPath $syncedAtPath) {
        (Get-Content -LiteralPath $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim()
    } else { '' }
    # Local-first ONLY when this session already fetched server exported-at into
    # CursorGoldenStampCache AND it matches local stamp. Never invent Current=true
    # from file mtime alone (that left laptops on the old Cursor account for up to
    # 60 minutes after golden rotation / account change).
    if ($syncedAt -and $script:CursorGoldenStampCache -and $script:CursorGoldenStampCache.Stamp) {
        $cached = [string]$script:CursorGoldenStampCache.Stamp
        if ($cached -and ($syncedAt -eq $cached)) {
            return [PSCustomObject]@{
                Current          = $true
                SyncedAt         = $syncedAt
                GoldenExportedAt = $cached
                Source           = 'session_cache'
            }
        }
    }
    $goldenExportedAt = Get-CursorGoldenExportedAtStamp -Alias $Alias
    return [PSCustomObject]@{
        Current          = [bool]($goldenExportedAt -and ($syncedAt -eq $goldenExportedAt))
        SyncedAt         = $syncedAt
        GoldenExportedAt = $goldenExportedAt
        Source           = 'ssh'
    }
}

function Test-CursorAuthNeedsRefresh {
    param([string]$DbPath = '', [bool]$AuthComplete = $false)
    $reasons = @()

    if (-not $DbPath) {
        $DbPath = Join-Path (Get-LocalCursorGlobalStorage) 'state.vscdb'
    }

    if (-not (Test-Path $DbPath)) {
        return [PSCustomObject]@{
            NeedsRefresh = $true
            Reasons      = @('db_missing')
        }
    }

    if (-not (Initialize-CursorAuthSqlite)) {
        return [PSCustomObject]@{
            NeedsRefresh = $true
            Reasons      = @('sqlite_unavailable')
        }
    }

    try {
        if (-not [CursorAuthSqlite]::HasNonEmptyValue($DbPath, 'storage.serviceMachineId')) {
            $reasons += 'serviceMachineId_empty'
        }
    } catch {
        $reasons += 'serviceMachineId_check_failed'
    }

    # Golden known-missing (cached, short TTL) - skip both remaining SSH round trips.
    # With no golden bundle there is nothing to compare machineid/exported-at against,
    # so these checks can never contribute a reason anyway; they were just re-proving
    # "still missing" on every single connect at full SSH round-trip cost.
    $goldenKnownMissing = Test-CursorGoldenKnownMissing

    # Electron machineid file must match golden (login breaks when it drifts).
    if (-not $goldenKnownMissing) {
    try {
        $profileDir = Get-CursorRemoteProfileDir
        $fileMid = ''
        $midPath = Join-Path $profileDir 'machineid'
        if (Test-Path -LiteralPath $midPath) {
            $fileMid = (Get-Content -LiteralPath $midPath -Raw -ErrorAction SilentlyContinue).Trim()
        }
        $goldMid = ''
        if (Get-Command SshX -ErrorAction SilentlyContinue) {
            $goldMid = ((SshX "tr -d '[:space:]' < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null") -join '').Trim()
        }
        if ($goldMid -and ($fileMid -ne $goldMid)) {
            $reasons += 'machineid_file_mismatch'
            Write-AuthSyncLog "AUTH ERROR machineid_file_mismatch" 'WARN'
        }
    } catch {
        $reasons += 'machineid_file_check_failed'
    }
    }

    # Golden token rotates ~6h; skip-forever when editor open must still detect stale stamp.
    if (-not $goldenKnownMissing) {
    try {
        $gs = Split-Path -Parent $DbPath
        $syncedAtPath = Join-Path $gs 'golden-synced-at.txt'
        $syncedAt = if (Test-Path -LiteralPath $syncedAtPath) {
            (Get-Content -LiteralPath $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim()
        } else { '' }
        $goldenExportedAt = ''
        if (Get-Command SshX -ErrorAction SilentlyContinue) {
            $goldenExportedAt = ((SshX "cat /etc/cursor-auth/golden/exported-at 2>/dev/null") -join '').Trim()
        }
        if ($goldenExportedAt -and ($syncedAt -ne $goldenExportedAt)) {
            $reasons += 'golden_stale'
            Write-AuthSyncLog "AUTH ERROR golden_stale synced_at='$syncedAt' exported_at='$goldenExportedAt'" 'WARN'
        }
    } catch {
        $reasons += 'golden_stale_check_failed'
    }
    }

    $personalMain = 0
    $profileMain = 0
    if (Get-Command Get-CursorMainPersonalProcesses -ErrorAction SilentlyContinue) {
        $personalMain = @(Get-CursorMainPersonalProcesses).Count
    }
    if (Get-Command Get-CursorMainProfileProcesses -ErrorAction SilentlyContinue) {
        $profileMain = @(Get-CursorMainProfileProcesses).Count
    }
    if ($personalMain -gt 0 -and $profileMain -eq 0 -and -not $AuthComplete) {
        Write-AuthSyncLog (
            "personal Cursor active without server profile (personal_main=$personalMain profile_main=$profileMain) - auth needs refresh"
        ) 'WARN'
        $reasons += 'personal_without_profile'
    }

    return [PSCustomObject]@{
        NeedsRefresh = ($reasons.Count -gt 0)
        Reasons      = $reasons
        PersonalMain = $personalMain
        ProfileMain  = $profileMain
    }
}

function Repair-CursorComposerWorkspaceBindings {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    return $true
}

function Write-AuthPerfLog {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Extra = ''
    )
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark $Mark -Ms $Ms -Extra $Extra
    } else {
        Write-AuthSyncLog "PERF[$Mark] ms=$Ms $Extra" 'DEBUG'
    }
}

function Sync-CursorGoldenAuth {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [switch]$Force,
        [string]$RemotePath = ''
    )

    $authTotalSw = [System.Diagnostics.Stopwatch]::StartNew()

    $localGs = Get-LocalCursorGlobalStorage
    $dbPath = Join-Path $localGs 'state.vscdb'
    $storagePath = Join-Path $localGs 'storage.json'
    $syncedAtPath = Join-Path $localGs 'golden-synced-at.txt'
    $dbBytes = if (Test-Path $dbPath) { (Get-Item $dbPath).Length } else { 0 }
    $walBytes = if (Test-Path "$dbPath-wal") { (Get-Item "$dbPath-wal").Length } else { 0 }

    Write-AuthSyncLog "AUTH_SYNC: begin force=$Force db_bytes=$dbBytes wal_bytes=$walBytes alias=$Alias remote_path=$RemotePath" 'INFO'
    # Mid-session AUTH: avoid merge into a huge open profile DB (chat freeze / WAL risk).
    # Threshold 500 MiB. Bypass when -Force OR golden stamp is already known-stale
    # (account rotation must land; large profiles were stuck on the old email).
    $authDbTooLarge = 524288000L
    $localSyncedAtEarly = if (Test-Path -LiteralPath $syncedAtPath) {
        (Get-Content -LiteralPath $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim()
    } else { '' }
    $prefetchStamp = ''
    if ($script:CursorGoldenStampCache -and $script:CursorGoldenStampCache.Stamp) {
        $prefetchStamp = [string]$script:CursorGoldenStampCache.Stamp
    }
    $goldenKnownStale = $false
    if ($prefetchStamp -and $localSyncedAtEarly -and ($prefetchStamp -ne $localSyncedAtEarly)) {
        $goldenKnownStale = $true
    }
    if (-not $Force -and -not $goldenKnownStale -and $dbBytes -gt $authDbTooLarge) {
        Write-AuthSyncLog ("AUTH_SYNC_SKIP: reason=db_too_large db_bytes={0} threshold={1}" -f $dbBytes, $authDbTooLarge) 'WARN'
        return [PSCustomObject]@{ Ok = $false; Skipped = $true; Reason = 'db_too_large' }
    }
    if (-not $Force -and $goldenKnownStale -and $dbBytes -gt $authDbTooLarge) {
        Write-AuthSyncLog ("AUTH_SYNC: bypass db_too_large reason=golden_stale db_bytes={0} synced_at={1} golden_exported_at={2}" -f $dbBytes, $localSyncedAtEarly, $prefetchStamp) 'WARN'
    }
    # If we already saw exported-at this session (stamp prefetch), golden is NOT missing.
    if ($script:CursorGoldenStampCache -and $script:CursorGoldenStampCache.Stamp) {
        Clear-CursorGoldenMissingCache
    }
    if (-not $Force -and (Test-CursorGoldenKnownMissing)) {
        # Prior successful sync proves golden existed; never stay stuck on a stale
        # negative cache (permission blips used to pin golden_missing_cached).
        if (Test-Path -LiteralPath $syncedAtPath) {
            Clear-CursorGoldenMissingCache
            Write-AuthSyncLog 'AUTH: cleared_stale_golden_missing_cache reason=synced_at_present' 'WARN'
        } else {
            Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_missing_cached db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
            $authTotalSw.Stop()
            Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_golden_missing_cached'
            return [PSCustomObject]@{ Ok = $false; Skipped = $true; Reason = 'golden_missing_cached' }
        }
    }
    # AUTH_SYNC_BATCH_PROBE: one SSH for golden existence + exported-at (was 2 round-trips).
    $swProbe = [System.Diagnostics.Stopwatch]::StartNew()
    $probeRaw = (SshX @'
if [ -f /etc/cursor-auth/golden/auth.json ]; then
  echo YES
  cat /etc/cursor-auth/golden/exported-at 2>/dev/null
else
  echo NO
fi
'@ 2>$null) -join "`n"
    $swProbe.Stop()
    $probeLines = @($probeRaw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $probe = if ($probeLines.Count -gt 0 -and $probeLines[0] -eq 'YES') { 'yes' } else { 'no' }
    $goldenExportedAt = if ($probe -eq 'yes' -and $probeLines.Count -gt 1) { $probeLines[1] } else { '' }
    Write-AuthPerfLog -Mark 'auth_ssh_probe' -Ms $swProbe.ElapsedMilliseconds -Extra "golden_exists=$($probe -eq 'yes') batched=1"
    if ($probe -ne 'yes') {
        Set-CursorGoldenMissingCache
        Write-AuthSyncLog 'skip golden auth.json missing on server' 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_missing db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_golden_missing'
        return [PSCustomObject]@{ Ok = $false; Skipped = $true; Reason = 'golden_missing' }
    }
    Clear-CursorGoldenMissingCache
    Write-AuthPerfLog -Mark 'auth_ssh_golden_meta' -Ms 0 -Extra 'batched_into_probe'

    Write-AuthSyncLog "local_gs=$localGs db=$dbPath db_exists=$(Test-Path $dbPath)" 'DEBUG'

    # The golden token rotates every 6h (cursor-auth-refresh); a merge that was "complete" at
    # the time still goes stale once the server issues a new token, since OAuth refresh_token
    # rotation invalidates the old accessToken/refreshToken pair. Presence alone can't detect
    # that, so also require the local copy to be stamped with the CURRENT golden export.
    # IMPORTANT: check already-complete BEFORE cursor-auth-sync --force (was wasting ~3-5s).
    $syncedAt = if (Test-Path $syncedAtPath) { (Get-Content $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    $goldenCurrent = $goldenExportedAt -and ($syncedAt -eq $goldenExportedAt)
    # Late size gate: if probe proved golden_stale, never block on db_too_large (account rotation).
    if (-not $Force -and -not $goldenCurrent -and $dbBytes -gt $authDbTooLarge -and $goldenExportedAt) {
        Write-AuthSyncLog ("AUTH_SYNC: bypass db_too_large reason=golden_stale_after_probe db_bytes={0} synced_at={1} golden_exported_at={2}" -f $dbBytes, $syncedAt, $goldenExportedAt) 'WARN'
    }
    # Single OpenDb session gives us both the completeness gate and serviceMachineId
    # in one read (Get-LocalCursorAuthState) instead of two separate SQLite opens.
    $localAuthState = Get-LocalCursorAuthState -DbPath $dbPath
    if (-not $Force -and $goldenCurrent -and $localAuthState.Complete) {
        # Heal Electron machineid from the local SQLite value already fetched above -
        # only fall back to an scp of golden machine-id.txt when the local read is empty.
        $midHealed = Heal-CursorProfileMachineIdFromLocal -DbPath $dbPath -KnownState $localAuthState
        if (-not $midHealed) {
            try {
                $goldMidDir = Join-Path (Get-CursorAuthTempRoot) ("claude-golden-mid-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path $goldMidDir | Out-Null
                $goldMidFile = Join-Path $goldMidDir 'machine-id.txt'
                scp -o BatchMode=yes -o ConnectTimeout=10 -q "${Alias}:/etc/cursor-auth/golden/machine-id.txt" $goldMidFile 2>$null
                if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $goldMidFile)) {
                    $fallbackMid = (Get-Content -LiteralPath $goldMidFile -Raw -ErrorAction SilentlyContinue).Trim()
                    if ($fallbackMid) { Write-CursorProfileMachineId -MachineId $fallbackMid | Out-Null; $midHealed = $true }
                }
                Remove-CursorAuthTempDir -Path $goldMidDir
            } catch { }
        }
        Write-AuthSyncLog "skip already complete golden_exported_at=$goldenExportedAt (machineid healed local=$midHealed)" 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=true skipped=true already_complete=true db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_already_complete'
        return [PSCustomObject]@{
            Ok              = $true
            Skipped         = $true
            AlreadyComplete = $true
        }
    }

    Write-AuthSyncLog 'server cursor-auth-sync --force' 'TRACE'
    $swServerSync = [System.Diagnostics.Stopwatch]::StartNew()
    SshX "cursor-auth-sync --force 2>&1" 2>$null | Out-Null
    $swServerSync.Stop()
    Write-AuthPerfLog -Mark 'auth_ssh_server_sync' -Ms $swServerSync.ElapsedMilliseconds

    $swGoldenScp = [System.Diagnostics.Stopwatch]::StartNew()
    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias
    $swGoldenScp.Stop()
    Write-AuthPerfLog -Mark 'auth_golden_scp' -Ms $swGoldenScp.ElapsedMilliseconds -Extra "ok=$([bool]$authValues)"
    if (-not $authValues) {
        Write-AuthSyncLog 'fail could not read golden bundle from server' 'WARN'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_read_failed db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=golden_read_failed'
        return [PSCustomObject]@{ Ok = $false; Skipped = $true; Reason = 'golden_read_failed' }
    }
    Write-AuthSyncLog "golden keys=$($authValues.PSObject.Properties.Name -join ',')" 'TRACE'

    if (-not (Initialize-CursorAuthSqlite)) {
        Write-AuthSyncLog 'fail sqlite not available' 'WARN'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=false reason=sqlite_missing db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=sqlite_missing'
        return [PSCustomObject]@{
            Ok            = $false
            Skipped       = $false
            SqliteMissing = $true
        }
    }

    $swMerge = [System.Diagnostics.Stopwatch]::StartNew()
    $merged = Merge-CursorAuthIntoLocalDb -DbPath $dbPath -AuthValues $authValues
    $swMerge.Stop()
    Write-AuthPerfLog -Mark 'auth_merge_db' -Ms $swMerge.ElapsedMilliseconds -Extra "ok=$merged"
    if (-not $merged) {
        Write-AuthSyncLog "fail merge into $dbPath" 'WARN'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=false reason=merge_failed db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=merge_failed'
        return [PSCustomObject]@{
            Ok          = $false
            Skipped     = $false
            MergeFailed = $true
        }
    }

    $swStorage = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Merge-CursorStorageJsonFromGolden -Alias $Alias -LocalPath $storagePath
    $swStorage.Stop()
    Write-AuthPerfLog -Mark 'auth_merge_storage' -Ms $swStorage.ElapsedMilliseconds

    $dbBytes = if (Test-Path $dbPath) { (Get-Item $dbPath).Length } else { 0 }
    $walBytes = if (Test-Path "$dbPath-wal") { (Get-Item "$dbPath-wal").Length } else { 0 }
    $complete = Test-LocalCursorAuthComplete -DbPath $dbPath
    if ($complete -and $goldenExportedAt) {
        Set-Content -Path $syncedAtPath -Value $goldenExportedAt -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
    }
    $tokens = Test-LocalCursorAuthDb -DbPath $dbPath
    Write-AuthSyncLog "done complete=$complete tokens_only=$($tokens -and -not $complete)" 'INFO'
    Write-AuthSyncLog (
        "AUTH_SYNC: result force=$Force ok=$complete skipped=false tokens_only=$($tokens -and -not $complete) " +
        "db_bytes=$dbBytes wal_bytes=$walBytes"
    ) 'INFO'
    $authTotalSw.Stop()
    Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra "ok=$complete tokens_only=$($tokens -and -not $complete)"
    return [PSCustomObject]@{
        Ok         = $complete
        TokensOnly = ($tokens -and -not $complete)
        Skipped    = $false
    }
}

