from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1')
t = p.read_text(encoding='utf-8')
old = '''    try {
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new(
            $script:ConnectLogPath, $true, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        return
    }'''
new = '''    try {
        # FileShare.ReadWrite: second connect (or leftover session) must not silently disable logging.
        $fs = [System.IO.FileStream]::new(
            $script:ConnectLogPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        try { Write-Host ("[WARN] connect log open failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow } catch { }
        return
    }'''
if old not in t:
    raise SystemExit('block not found')
p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='\n')
print('fixed FileShare.ReadWrite')
