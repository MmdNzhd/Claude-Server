from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1')
t = p.read_text(encoding='utf-8')
old = '''if ($failed.Count -gt 0) {
    Write-UpdateMsg "[!] Update incomplete ($($failed.Count) files missing in bundle) - using local copy" 'DarkYellow'
    exit 0
}'''
new = '''if ($failed.Count -gt 0) {
    Write-UpdateMsg "[!] Update incomplete ($($failed.Count) files missing in bundle) - using local copy" 'DarkYellow'
    Write-UpdateFileLog ("incomplete_files=$($failed.Count) sample=$($failed[0])") 'ERROR'
    exit 0
}'''
if old not in t:
    raise SystemExit('block not found')
p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='\n')
print('fixed')
