from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\write_edge_fixes.ps1')
text = p.read_text(encoding='utf-8')
start = text.find("@'")
end = text.find("'@ | Set-Content")
if start < 0 or end < start:
    raise SystemExit(f'markers not found start={start} end={end}')
body = text[start+2:end]
if body.startswith('\n'):
    body = body[1:]
body = body.replace('\r\n', '\n').replace('\r', '\n')
out = Path(r'D:\Smart\Claude-Code-Server\scripts\server\claude-self-heal.sh')
out.write_bytes(body.encode('utf-8'))
print('wrote', out, 'bytes', out.stat().st_size)
for m in ('_heal_active_remount', '_heal_connect_log_bufs', '_heal_zombie_readable', '_infer_active_mount', '_heal_bashrc_timeout'):
    print(m, m in body)
