from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\server\claude-connect-logs-cleanup.sh')
t = p.read_text(encoding='utf-8')
t = t.replace('older than 1 day', 'older than 7 days')
t = t.replace('mtime +1', 'mtime +7')
p.write_text(t, encoding='utf-8', newline='\n')
print('cleanup OK')
