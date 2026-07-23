#Requires -Version 5.1
# cursor-profile-db-tool.ps1 - Stage 10: MANUAL report/prune for ClaudeServerCursorProfile DBs.
# NEVER wire into connect.bat / connect.ps1 / connect-boot auto path.
#
# Usage:
#   powershell -NoProfile -File scripts\client\cursor-profile-db-tool.ps1 -Report
#   powershell -NoProfile -File scripts\client\cursor-profile-db-tool.ps1 -PruneChatAgent -Force
#
# -PruneChatAgent refuses unless every Cursor process using the server profile is closed.
# -Force is required for prune (safety latch); it does NOT kill processes.

[CmdletBinding(DefaultParameterSetName = 'Report')]
param(
    [Parameter(ParameterSetName = 'Report')][switch]$Report,
    [Parameter(ParameterSetName = 'Prune', Mandatory)][switch]$PruneChatAgent,
    [Parameter(ParameterSetName = 'Prune')][switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'editor-launch.ps1')

function Test-CursorServerProfileClosed {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    $procs = @(Get-CursorProfileProcesses -ProfileDir $ProfileDir -ForceRefresh)
    return ($procs.Count -eq 0)
}

function Get-ProfileDbPaths {
    $profileDir = Get-CursorRemoteProfileDir
    $userDir = Join-Path $profileDir 'User'
    $gs = Join-Path $userDir 'globalStorage'
    $db = Join-Path $gs 'state.vscdb'
    $ws = Join-Path $userDir 'workspaceStorage'
    return [pscustomobject]@{
        ProfileDir = $profileDir
        UserDir    = $userDir
        GlobalDb   = $db
        Workspace  = $ws
    }
}

function Invoke-SqliteScalar {
    param([Parameter(Mandatory)][string]$DbPath, [Parameter(Mandatory)][string]$Sql)
    if (-not (Test-Path -LiteralPath $DbPath)) { return $null }
    $tmpPy = Join-Path $env:TEMP ("cursor-db-tool-{0}.py" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $tmpSql = Join-Path $env:TEMP ("cursor-db-tool-{0}.sql" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        @(
            'import sqlite3, sys'
            'db = sys.argv[1]'
            'sql = open(sys.argv[2], encoding="utf-8").read()'
            'conn = sqlite3.connect(db)'
            'try:'
            '    row = conn.execute(sql).fetchone()'
            '    print(row[0] if row and row[0] is not None else "")'
            'finally:'
            '    conn.close()'
        ) -join "`n" | Set-Content -LiteralPath $tmpPy -Encoding UTF8
        Set-Content -LiteralPath $tmpSql -Value $Sql -Encoding UTF8
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $out = & python $tmpPy $DbPath $tmpSql 2>$null
        } finally {
            $ErrorActionPreference = $prev
        }
        return $out
    } finally {
        Remove-Item -LiteralPath $tmpPy, $tmpSql -Force -ErrorAction SilentlyContinue
    }
}

function Write-ProfileReport {
    $paths = Get-ProfileDbPaths
    $closed = Test-CursorServerProfileClosed -ProfileDir $paths.ProfileDir
    $dbBytes = if (Test-Path -LiteralPath $paths.GlobalDb) { (Get-Item -LiteralPath $paths.GlobalDb).Length } else { 0 }
    $walBytes = if (Test-Path -LiteralPath ($paths.GlobalDb + '-wal')) { (Get-Item -LiteralPath ($paths.GlobalDb + '-wal')).Length } else { 0 }
    $wsDirs = 0
    if (Test-Path -LiteralPath $paths.Workspace) {
        $wsDirs = @(Get-ChildItem -LiteralPath $paths.Workspace -Directory -ErrorAction SilentlyContinue).Count
    }
    $composerKv = 0
    $composerHeaders = 0
    if (Test-Path -LiteralPath $paths.GlobalDb) {
        $kv = Invoke-SqliteScalar -DbPath $paths.GlobalDb -Sql "SELECT count(*) FROM cursorDiskKV WHERE key LIKE 'composerData:%'"
        if ($kv -match '^\d+$') { $composerKv = [int]$kv }
        $hdr = Invoke-SqliteScalar -DbPath $paths.GlobalDb -Sql "SELECT length(value) FROM ItemTable WHERE key='composer.composerHeaders'"
        if ($hdr -match '^\d+$') { $composerHeaders = [int]$hdr }
    }

    Write-Host ''
    Write-Host '=== Cursor server profile DB report (manual tool) ===' -ForegroundColor Cyan
    Write-Host ("profile_dir={0}" -f $paths.ProfileDir)
    Write-Host ("profile_cursor_closed={0}" -f ($(if ($closed) { 'yes' } else { 'no' })))
    Write-Host ("state_vscdb_bytes={0}" -f $dbBytes)
    Write-Host ("state_vscdb_wal_bytes={0}" -f $walBytes)
    Write-Host ("workspaceStorage_dirs={0}" -f $wsDirs)
    Write-Host ("composerData_kv_count={0}" -f $composerKv)
    Write-Host ("composerHeaders_value_len={0}" -f $composerHeaders)
    Write-Host 'NOTE: not wired into connect auto path. Prune only with -PruneChatAgent -Force when closed.'
    Write-Host ''
    return 0
}

function Invoke-PruneChatAgent {
    if (-not $Force) {
        Write-Host '  [X] REFUSE prune: -Force required (safety latch; does not kill Cursor).' -ForegroundColor Red
        return 2
    }
    $paths = Get-ProfileDbPaths
    if (-not (Test-CursorServerProfileClosed -ProfileDir $paths.ProfileDir)) {
        Write-Host '  [X] REFUSE prune: server-profile Cursor still running (close all ClaudeServerCursorProfile windows first).' -ForegroundColor Red
        return 3
    }
    if (-not (Test-Path -LiteralPath $paths.GlobalDb)) {
        Write-Host '  [i] No state.vscdb — nothing to prune.' -ForegroundColor Yellow
        return 0
    }

    $tmpPy = Join-Path $env:TEMP ("cursor-db-prune-{0}.py" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        @(
            'import sqlite3, sys'
            'db = sys.argv[1]'
            'conn = sqlite3.connect(db)'
            'try:'
            '    cur = conn.cursor()'
            '    deleted = 0'
            '    try:'
            '        cur.execute("DELETE FROM cursorDiskKV WHERE key LIKE ''composerData:%'' OR key LIKE ''bubbleId:%'' OR key LIKE ''agentKv:%''")'
            '        deleted += cur.rowcount if cur.rowcount and cur.rowcount > 0 else 0'
            '    except sqlite3.Error:'
            '        pass'
            '    try:'
            '        cur.execute("DELETE FROM ItemTable WHERE key LIKE ''composer.%'' OR key LIKE ''workbench.panel.aichat%'' OR key LIKE ''aichat.%''")'
            '        deleted += cur.rowcount if cur.rowcount and cur.rowcount > 0 else 0'
            '    except sqlite3.Error:'
            '        pass'
            '    conn.commit()'
            '    try:'
            '        conn.execute("VACUUM")'
            '    except sqlite3.Error:'
            '        pass'
            '    print("deleted_rows=%d" % deleted)'
            'finally:'
            '    conn.close()'
        ) -join "`n" | Set-Content -LiteralPath $tmpPy -Encoding UTF8
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $out = & python $tmpPy $paths.GlobalDb 2>&1 | Out-String
        } finally {
            $ErrorActionPreference = $prev
        }
        Write-Host ("  OK prune chat/agent keys ({0})" -f $out.Trim()) -ForegroundColor Green
        return 0
    } finally {
        Remove-Item -LiteralPath $tmpPy -Force -ErrorAction SilentlyContinue
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Prune') {
    exit (Invoke-PruneChatAgent)
}
exit (Write-ProfileReport)
