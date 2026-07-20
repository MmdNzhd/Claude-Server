from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\deep-report-final.ps1')
t = p.read_text(encoding='utf-8-sig')
t = t.replace('($warn warnings)', '(${warn} warnings)')
t = t.replace('$fail fail / $warn warn', '${fail} fail / ${warn} warn')
p.write_text(t, encoding='utf-8', newline='')
print('ok')
