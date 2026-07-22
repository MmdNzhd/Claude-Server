import sqlite3, os, collections
db = os.path.join(os.environ['LOCALAPPDATA'], r'ClaudeServerCursorProfile\User\globalStorage\state.vscdb')
con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
cur = con.cursor()
print('=== cursorDiskKV size by key family ===')
# Aggregate by prefix before first ':' or first two segments
agg = collections.Counter()
cnt = collections.Counter()
# streaming to avoid huge memory - just key and length
for k, n in cur.execute('SELECT key, LENGTH(value) FROM cursorDiskKV'):
    if k.startswith('bubbleId:'):
        fam = 'bubbleId (chat/agent messages)'
    elif k.startswith('agentKv:'):
        fam = 'agentKv (agent blobs/cache)'
    elif k.startswith('composerData:'):
        fam = 'composerData (composer chats)'
    elif k.startswith('composerContent:'):
        fam = 'composerContent'
    elif k.startswith('checkpointId:') or k.startswith('checkpoint:'):
        fam = 'checkpoint'
    elif k.startswith('codeBlockDiff:') or 'codeBlock' in k[:40]:
        fam = 'codeBlock*'
    else:
        fam = (k.split(':', 1)[0] if ':' in k else k[:40])
    agg[fam] += (n or 0)
    cnt[fam] += 1
for fam, b in agg.most_common(20):
    print(f'{b/1024/1024:.1f} MB\trows={cnt[fam]}\t{fam}')
print('total_rows', sum(cnt.values()), 'total_GB', round(sum(agg.values())/1024**3, 2))
# composerHeaders
try:
    n = cur.execute('SELECT COUNT(*) FROM composerHeaders').fetchone()[0]
    b = cur.execute('SELECT COALESCE(SUM(LENGTH(value)),0) FROM composerHeaders').fetchone()[0]
    print(f'composerHeaders rows={n} MB={b/1024/1024:.2f}')
except Exception as e:
    print(e)
con.close()
