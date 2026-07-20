from pathlib import Path
cp=Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1').read_text(encoding='utf-8')
# around 1480-1550
lines=cp.splitlines()
for i in range(1470, min(1580,len(lines))):
    print(f'{i+1}:{lines[i]}')
print('==== Test-ConnectPerfEnabled full ====')
ui=Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1').read_text(encoding='utf-8')
a=ui.find('function Test-ConnectPerfEnabled')
print(ui[a:a+200])
# Write-GitModeLog 
gm=Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1').read_text(encoding='utf-8')
b=gm.find('function Write-GitModeLog')
print(gm[b:b+350])
