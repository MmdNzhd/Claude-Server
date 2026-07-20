from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
cp = root / 'scripts/client/windows/connect.ps1'
ct = cp.read_text(encoding='utf-8')

# Remove mux helpers and restore clean Invoke-SshXCore (no ControlMaster)
m = re.search(
    r'(?s)function Get-ConnectSshMuxPath \{.*?function Invoke-SshXCore \{.*?^\}\r?\n\r?\nfunction SshX',
    ct,
    re.M,
)
if not m:
    # try without Get-Connect if already partially removed
    raise SystemExit('mux/core block not found')

restored = '''function Invoke-SshXCore {
    param([Parameter(Mandatory)][string]$RemoteCmd)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # No ControlMaster on Windows OpenSSH here: ControlPath/named-pipe mux fails with
    # "getsockname failed: Not a socket" and breaks SshX. Speedups stay in batched remote cmds.
    $lines = @(& ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 `
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $Alias $RemoteCmd 2>&1)
    $sw.Stop()
    if ($null -eq $lines) { $lines = @() }
    return [PSCustomObject]@{
        Exit = $LASTEXITCODE
        Ms   = [int]$sw.ElapsedMilliseconds
        Out  = ($lines -join "`n")
        Lines = $lines
    }
}

function SshX'''

ct = ct[:m.start()] + restored + ct[m.end():]
cp.write_text(ct, encoding='utf-8', newline='\n')
print('removed mux from connect.ps1')

# Remove Stop-ConnectSshMux from Close-ConnectLog
ui = root / 'scripts/client/connect-ui.ps1'
ut = ui.read_text(encoding='utf-8')
ut2 = ut.replace(
    'if (Get-Command Stop-ConnectSshMux -ErrorAction SilentlyContinue) { Stop-ConnectSshMux }\n    Exit-ConnectSingleInstance',
    'Exit-ConnectSingleInstance',
)
ut2 = ut2.replace(
    'if (Get-Command Stop-ConnectSshMux -ErrorAction SilentlyContinue) { Stop-ConnectSshMux }\r\n    Exit-ConnectSingleInstance',
    'Exit-ConnectSingleInstance',
)
# also any leftover
ut2 = re.sub(
    r'\s*if \(Get-Command Stop-ConnectSshMux -ErrorAction SilentlyContinue\) \{ Stop-ConnectSshMux \}\s*\n\s*Exit-ConnectSingleInstance',
    '\n    Exit-ConnectSingleInstance',
    ut2,
)
ui.write_text(ut2, encoding='utf-8', newline='\n')
print('cleaned Close-ConnectLog')

# bump .20 stays or .21? keep .20 with fix note - still .20 is fine as mux never published if we republish
# actually .20 may have been only local - we'll publish fixed .20
print('version still', (root/'scripts/client/windows/connect-version.txt').read_text().strip())
print('DONE')
