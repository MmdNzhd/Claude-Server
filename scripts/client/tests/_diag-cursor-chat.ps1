# _diag-cursor-chat.ps1 - read-only chat storage diagnostic (no secrets printed)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\editor-launch.ps1')

$profile = Join-Path (Get-CursorRemoteProfileDir) 'User'
$gs = Join-Path $profile 'globalStorage\state.vscdb'
$wsRoot = Join-Path $profile 'workspaceStorage'

Write-Host "Profile: $profile"
Write-Host "globalStorage: $(Test-Path $gs)"

if (Test-Path $gs) {
    $py = @'
import sqlite3, sys, json
db = sys.argv[1]
c = sqlite3.connect(db)
composer_keys = [r[0] for r in c.execute("SELECT key FROM ItemTable WHERE key LIKE 'composer%'").fetchall()]
kv = c.execute("SELECT count(*) FROM cursorDiskKV WHERE key LIKE 'composerData:%'").fetchone()[0]
headers = c.execute("SELECT value FROM ItemTable WHERE key='composer.composerHeaders'").fetchone()
print('composer_item_keys', len(composer_keys))
print('composerData_count', kv)
if headers:
    try:
        h = json.loads(headers[0])
        ac = h.get('allComposers') or []
        print('composerHeaders_count', len(ac))
        for item in ac[:5]:
            wi = item.get('workspaceIdentifier') or {}
            uri = wi.get('uri') or {}
            ext = uri.get('external') or uri.get('fsPath') or wi.get('id') or ''
            print('  header', item.get('name','?')[:40], '|', str(ext)[:80])
    except Exception as e:
        print('composerHeaders_parse_error', e)
c.close()
'@
    $env:_CHAT_DB = $gs
    python -c $py $gs
}

if (Test-Path $wsRoot) {
    Write-Host ''
    Write-Host 'workspaceStorage folders matching ai-gap / claude-server:'
    Get-ChildItem $wsRoot -Directory | ForEach-Object {
        $wj = Join-Path $_.FullName 'workspace.json'
        if (-not (Test-Path $wj)) { return }
        $raw = Get-Content $wj -Raw | ConvertFrom-Json
        $folder = [string]$raw.folder
        if ($folder -notmatch 'ai-gap|gap-summ|Claude-Code-Server|claude-server') { return }
        Write-Host "  $($_.Name)"
        Write-Host "    $folder"
        $wdb = Join-Path $_.FullName 'state.vscdb'
        if (Test-Path $wdb) {
            $py2 = @'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
row = c.execute("SELECT value FROM ItemTable WHERE key='composer.composerData'").fetchone()
if row:
    j = json.loads(row[0])
    ac = j.get('allComposers') or []
    print('  allComposers', len(ac))
    print('  migrated', j.get('hasMigratedComposerData'))
    for x in ac[:3]:
        print('   ', x.get('composerId','?')[:8], x.get('name','?')[:50])
else:
    print('  no composer.composerData')
c.close()
'@
            python -c $py2 $wdb
        }
    }
}
