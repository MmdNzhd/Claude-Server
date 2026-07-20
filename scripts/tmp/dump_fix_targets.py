from pathlib import Path
gm = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1').read_text(encoding='utf-8')
ui = Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1').read_text(encoding='utf-8')
upd = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1').read_text(encoding='utf-8')
bat = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.bat').read_text(encoding='utf-8', errors='replace')

# STALE wait loop
i = gm.find('STALE_FORWARD: clearing')
print('=== STALE block ===')
print(gm[i-200:i+900])
print('=== PERF enable ===')
j = ui.find('function Test-ConnectPerfEnabled')
print(ui[j:j+400])
print('=== Write-ConnectPerfLog ===')
k = ui.find('function Write-ConnectPerfLog')
print(ui[k:k+350])
print('=== update end ===')
print(upd[-800:])
print('=== bat bootstrap ===')
print('\n'.join(bat.splitlines()[:25]))
# day path
print('=== Get-ConnectLogDayPath ===')
print(ui[ui.find('function Get-ConnectLogDayPath'):ui.find('function Get-ConnectLogDayPath')+250])
