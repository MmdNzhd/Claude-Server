from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\verify-launch-ultra-deep.ps1')
t = p.read_text(encoding='utf-8-sig')
t = t.replace('around L$orphanIdx:', 'around L${orphanIdx}:')
p.write_text(t, encoding='utf-8', newline='')
print('fixed')
