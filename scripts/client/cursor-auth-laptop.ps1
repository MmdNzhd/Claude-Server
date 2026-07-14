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

        if (_open == null || _close == null || _prepare == null || _bindText == null ||
            _step == null || _finalize == null || _busyTimeout == null || _columnInt == null)
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

function Get-RemoteCursorAuthFromGolden {
    param([Parameter(Mandatory)][string]$Alias)

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
        return (Build-CursorAuthValuesFromGoldenDir -GoldenDir $tmp)
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
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
        if ([CursorAuthSqlite]::MergeAuthValues($DbPath, $map)) { return $true }
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
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
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

function Test-CursorAuthNeedsRefresh {
    param([string]$DbPath = '')
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

    $personalMain = 0
    $profileMain = 0
    if (Get-Command Get-CursorMainPersonalProcesses -ErrorAction SilentlyContinue) {
        $personalMain = @(Get-CursorMainPersonalProcesses).Count
    }
    if (Get-Command Get-CursorMainProfileProcesses -ErrorAction SilentlyContinue) {
        $profileMain = @(Get-CursorMainProfileProcesses).Count
    }
    if ($personalMain -gt 0 -and $profileMain -eq 0) {
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

function Sync-CursorGoldenAuth {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [switch]$Force,
        [string]$RemotePath = ''
    )

    $skipped = [PSCustomObject]@{ Ok = $false; Skipped = $true }

    $localGs = Get-LocalCursorGlobalStorage
    $dbPath = Join-Path $localGs 'state.vscdb'
    $storagePath = Join-Path $localGs 'storage.json'
    $syncedAtPath = Join-Path $localGs 'golden-synced-at.txt'
    $dbBytes = if (Test-Path $dbPath) { (Get-Item $dbPath).Length } else { 0 }
    $walBytes = if (Test-Path "$dbPath-wal") { (Get-Item "$dbPath-wal").Length } else { 0 }

    Write-AuthSyncLog "AUTH_SYNC: begin force=$Force db_bytes=$dbBytes wal_bytes=$walBytes alias=$Alias remote_path=$RemotePath" 'INFO'
    $probe = (SshX "test -f /etc/cursor-auth/golden/auth.json && echo yes" 2>$null) -join ''
    if ($probe -notmatch 'yes') {
        Write-AuthSyncLog 'skip golden auth.json missing on server' 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_missing db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        return $skipped
    }
    $goldenExportedAt = ((SshX "cat /etc/cursor-auth/golden/exported-at 2>/dev/null") -join '').Trim()

    Write-AuthSyncLog 'server cursor-auth-sync --force' 'TRACE'
    SshX "cursor-auth-sync --force 2>&1" 2>$null | Out-Null

    Write-AuthSyncLog "local_gs=$localGs db=$dbPath db_exists=$(Test-Path $dbPath)" 'DEBUG'

    # The golden token rotates every 6h (cursor-auth-refresh); a merge that was "complete" at
    # the time still goes stale once the server issues a new token, since OAuth refresh_token
    # rotation invalidates the old accessToken/refreshToken pair. Presence alone can't detect
    # that, so also require the local copy to be stamped with the CURRENT golden export.
    $syncedAt = if (Test-Path $syncedAtPath) { (Get-Content $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    $goldenCurrent = $goldenExportedAt -and ($syncedAt -eq $goldenExportedAt)
    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
        Write-AuthSyncLog "skip already complete golden_exported_at=$goldenExportedAt" 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=true skipped=true already_complete=true db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        return [PSCustomObject]@{
            Ok              = $true
            Skipped         = $true
            AlreadyComplete = $true
        }
    }

    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias
    if (-not $authValues) {
        Write-AuthSyncLog 'fail could not read golden bundle from server' 'WARN'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_read_failed db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        return $skipped
    }
    Write-AuthSyncLog "golden keys=$($authValues.PSObject.Properties.Name -join ',')" 'TRACE'

    if (-not (Initialize-CursorAuthSqlite)) {
        Write-AuthSyncLog 'fail sqlite not available' 'WARN'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=false reason=sqlite_missing db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        return [PSCustomObject]@{
            Ok            = $false
            Skipped       = $false
            SqliteMissing = $true
        }
    }

    $merged = Merge-CursorAuthIntoLocalDb -DbPath $dbPath -AuthValues $authValues
    if (-not $merged) {
        Write-AuthSyncLog "fail merge into $dbPath" 'WARN'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=false reason=merge_failed db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        return [PSCustomObject]@{
            Ok          = $false
            Skipped     = $false
            MergeFailed = $true
        }
    }

    $null = Merge-CursorStorageJsonFromGolden -Alias $Alias -LocalPath $storagePath

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
    return [PSCustomObject]@{
        Ok         = $complete
        TokensOnly = ($tokens -and -not $complete)
        Skipped    = $false
    }
}

