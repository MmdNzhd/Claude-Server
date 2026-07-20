from pathlib import Path
ui=Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1').read_text(encoding='utf-8')
c0=ui.find('function Close-ConnectLog')
c1=ui.find('\nfunction ', c0+10)
print(ui[c0:c1])
print('---')
# mac connect.sh around init
sh=Path(r'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh').read_text(encoding='utf-8')
i=sh.find('init_connect_log')
print(sh[i-100:i+250])
