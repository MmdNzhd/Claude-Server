from pathlib import Path
ui = Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1').read_text(encoding='utf-8')
cp = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1').read_text(encoding='utf-8')
# Write-ConnectLog full
w0=ui.find('function Write-ConnectLog')
w1=ui.find('function Read-ConnectPrompt', w0)
print('=== Write-ConnectLog ===')
print(ui[w0:w1])
print('=== Initialize open block ===')
i0=ui.find('try {\n        # FileShare')
if i0<0: i0=ui.find('$script:ConnectLogWriter = [System.IO.StreamWriter]')
print(ui[i0:i0+700])
# connect.ps1 start - init log
for pat in ['Initialize-ConnectLog', 'Close-ConnectLog', 'param(', 'ConnectVersion']:
    idx=cp.find(pat)
    print(f'--- cp {pat} @ {idx} ---')
    if idx>=0: print(cp[max(0,idx-80):idx+200])
