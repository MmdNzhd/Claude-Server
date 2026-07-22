from pathlib import Path
p = Path('scripts/client/windows/connect-update.ps1')
t = p.read_text(encoding='utf-8')
old = '''    $got = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -ne $want) {
        Write-UpdateFileLog ("local_exe_drift local=$local") 'WARN'
        return $false
    }'''
new = '''    $fh = Get-FileHash -LiteralPath $local -Algorithm SHA256 -ErrorAction SilentlyContinue
    if (-not $fh -or -not $fh.PSObject.Properties['Hash'] -or -not $fh.Hash) {
        Write-UpdateFileLog ("local_exe_hash_fail local=$local") 'WARN'
        return $false
    }
    $got = ([string]$fh.Hash).ToLowerInvariant()
    if ($got -ne $want) {
        Write-UpdateFileLog ("local_exe_drift local=$local") 'WARN'
        return $false
    }'''
if old in t:
    p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='\n')
    print('hash harden OK')
elif 'local_exe_hash_fail' in t:
    print('hash already hardened')
else:
    print('WARN hash block not found')
