from pathlib import Path
import re
root = Path(r'D:/Smart/Claude-Code-Server')

# --- Add proxy helpers to connect-ui.ps1 before Set-ConnectTitle ---
ui_path = root / 'scripts/client/connect-ui.ps1'
ui = ui_path.read_text(encoding='utf-8').replace('\r\n','\n')
if 'function Get-WindowsSystemProxy' in ui:
    print('SKIP proxy helpers exist')
else:
    proxy_fn = r'''
function Get-WindowsSystemProxy {
    # Read user Internet Settings (+ WinHTTP fallback). Used when direct net fails.
    $result = [pscustomobject]@{ Enabled = $false; Server = ''; Bypass = ''; Source = 'none' }
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $enable = [int](Get-ItemProperty -Path $key -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
        $server = [string](Get-ItemProperty -Path $key -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
        $bypass = [string](Get-ItemProperty -Path $key -Name ProxyOverride -ErrorAction SilentlyContinue).ProxyOverride
        if ($enable -eq 1 -and $server) {
            $result.Enabled = $true
            $result.Server = $server.Trim()
            $result.Bypass = $bypass
            $result.Source = 'hkcu_internet_settings'
            return $result
        }
    } catch { }
    try {
        $out = (& netsh winhttp show proxy 2>$null | Out-String)
        if ($out -match 'Proxy Server\(s\)\s*:\s*(.+)') {
            $srv = $matches[1].Trim()
            if ($srv -and $srv -notmatch '(?i)direct') {
                $result.Enabled = $true
                $result.Server = $srv
                $result.Source = 'winhttp'
                if ($out -match 'Bypass List\s*:\s*(.+)') { $result.Bypass = $matches[1].Trim() }
            }
        }
    } catch { }
    return $result
}

function Apply-ConnectProxyEnvironment {
    param([string]$ServerIp = '')
    if (-not (Get-Command Get-WindowsSystemProxy -ErrorAction SilentlyContinue)) { return }
    $px = Get-WindowsSystemProxy
    if (-not $px.Enabled -or -not $px.Server) {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'PROXY: enabled=False source=none' 'DEBUG'
        }
        return
    }
    $server = [string]$px.Server
    # Internet Settings may be "http=host:port;https=host:port" — pick first host:port
    if ($server -match '(?i)(?:https?|socks)=([^;]+)') { $server = $matches[1].Trim() }
    elseif ($server -match ';') { $server = ($server -split ';')[0].Trim() }
    if ($server -notmatch '^[a-zA-Z]+://') { $serverUrl = "http://$server" } else { $serverUrl = $server }
    $env:HTTP_PROXY = $serverUrl
    $env:HTTPS_PROXY = $serverUrl
    $env:ALL_PROXY = $serverUrl
    $no = @('localhost', '127.0.0.1', '::1', '10.*', '192.168.*', '172.16.*', '172.17.*', '172.18.*', '172.19.*', '172.2*', '172.3*', '.local')
    if ($ServerIp) { $no += $ServerIp }
    if ($px.Bypass) {
        foreach ($b in ($px.Bypass -split '[,;]')) {
            $t = $b.Trim()
            if ($t -and $t -ne '<local>') { $no += $t }
        }
    }
    $env:NO_PROXY = ($no -join ',')
    $env:no_proxy = $env:NO_PROXY
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("PROXY: enabled=True server={0} source={1} no_proxy_set=1" -f $server, $px.Source) 'INFO'
    }
}

'''
    marker = 'function Set-ConnectTitle {'
    if marker not in ui:
        raise SystemExit('Set-ConnectTitle marker missing')
    ui = ui.replace(marker, proxy_fn + marker, 1)
    ui_path.write_text(ui, encoding='utf-8', newline='\n')
    print('OK added proxy helpers')

# Wire into connect.ps1 early after Initialize-ConnectLog / header
win_path = root / 'scripts/client/windows/connect.ps1'
win = win_path.read_text(encoding='utf-8').replace('\r\n','\n')
if 'Apply-ConnectProxyEnvironment' in win:
    print('SKIP proxy wire exists')
else:
    # after Write-ConnectHeader or Initialize-ConnectLog
    needle = 'Write-ConnectHeader -Alias $Alias -ServerIP $ServerIP -Version $script:ConnectVersion'
    if needle in win:
        insert = needle + "\n\nif (Get-Command Apply-ConnectProxyEnvironment -ErrorAction SilentlyContinue) {\n    Apply-ConnectProxyEnvironment -ServerIp $ServerIP\n}\n"
        win = win.replace(needle, insert, 1)
        win_path.write_text(win, encoding='utf-8', newline='\n')
        print('OK wired Apply-ConnectProxyEnvironment')
    else:
        print('MISS wire needle')

# Bump version to 20260720.11
ver = '20260720.11'
for rel in [
    'scripts/client/windows/connect-version.txt',
    'scripts/client/mac/connect-version.txt',
]:
    (root/rel).write_text(ver + '\n', encoding='utf-8', newline='\n')
    print('OK', rel, ver)

win = win_path.read_text(encoding='utf-8')
win2, n = re.subn(r"\$script:ConnectVersion = '20260720\.\d+'", f"$script:ConnectVersion = '{ver}'", win, count=1)
if n != 1:
    raise SystemExit('connect.ps1 version bump failed')
win_path.write_text(win2.replace('\r\n','\n'), encoding='utf-8', newline='\n')
print('OK connect.ps1 version')

mac = root / 'scripts/client/mac/connect.sh'
mt = mac.read_text(encoding='utf-8')
mt2, n = re.subn(r"CONNECT_VERSION='20260720\.\d+'", f"CONNECT_VERSION='{ver}'", mt, count=1)
if n != 1:
    raise SystemExit('mac version bump failed')
mac.write_text(mt2, encoding='utf-8', newline='\n')
print('OK mac connect.sh version')
print('DONE bump', ver)
