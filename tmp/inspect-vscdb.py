import sqlite3, os
db = os.path.join(os.environ['LOCALAPPDATA'], r'ClaudeServerCursorProfile\User\globalStorage\state.vscdb')
print('db', db)
print('size_gb', round(os.path.getsize(db)/1024**3, 2))
con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
cur = con.cursor()
print('=== tables ===')
for r in cur.execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','index') ORDER BY type, name"):
    print(r[0], r[1])
print('=== schema ===')
for r in cur.execute("SELECT sql FROM sqlite_master WHERE type='table'"):
    print((r[0] or '')[:400])

for table in ('ItemTable', 'cursorDiskKV'):
    try:
        n = cur.execute(f'SELECT COUNT(*) FROM [{table}]').fetchone()[0]
        print(f'count_{table}={n}')
    except Exception as e:
        print(f'{table}: {e}')

print('=== top 40 ItemTable by value bytes ===')
try:
    for k, n in cur.execute('SELECT key, LENGTH(value) FROM ItemTable ORDER BY LENGTH(value) DESC LIMIT 40'):
        print(f'{n/1024/1024:.2f} MB\t{k[:180]}')
except Exception as e:
    print('fail', e)
    print('cols', cur.execute('PRAGMA table_info(ItemTable)').fetchall())

print('=== top 20 cursorDiskKV ===')
try:
    for k, n in cur.execute('SELECT key, LENGTH(value) FROM cursorDiskKV ORDER BY LENGTH(value) DESC LIMIT 20'):
        print(f'{n/1024/1024:.2f} MB\t{k[:180]}')
except Exception as e:
    print(e)

page_count = cur.execute('PRAGMA page_count').fetchone()[0]
page_size = cur.execute('PRAGMA page_size').fetchone()[0]
freelist = cur.execute('PRAGMA freelist_count').fetchone()[0]
print(f'page_count={page_count} page_size={page_size} freelist={freelist}')
print(f'logical_GB={(page_count*page_size)/1024**3:.2f} free_GB={(freelist*page_size)/1024**3:.2f}')

print('=== size by key prefix ===')
try:
    q = '''
    SELECT
      CASE
        WHEN instr(key, '/') > 0 THEN substr(key, 1, instr(key, '/') - 1)
        WHEN instr(key, '.') > 0 THEN substr(key, 1, instr(key, '.') - 1)
        ELSE key
      END AS pref,
      COUNT(*) AS cnt,
      SUM(LENGTH(value)) AS bytes
    FROM ItemTable
    GROUP BY pref
    ORDER BY bytes DESC
    LIMIT 30
    '''
    for pref, cnt, b in cur.execute(q):
        print(f'{(b or 0)/1024/1024:.2f} MB\trows={cnt}\t{pref}')
except Exception as e:
    print('prefix', e)

# sample a few huge keys: type of content
print('=== sample head of top 5 values ===')
try:
    for k, n, v in cur.execute('SELECT key, LENGTH(value), substr(value,1,120) FROM ItemTable ORDER BY LENGTH(value) DESC LIMIT 5'):
        preview = repr(v)[:200]
        print(f'--- {n/1024/1024:.2f} MB key={k[:120]}')
        print(preview)
except Exception as e:
    print(e)
con.close()
