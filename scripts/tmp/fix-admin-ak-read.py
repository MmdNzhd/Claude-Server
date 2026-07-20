from pathlib import Path
import re

p = Path('scripts/client/windows/connect.ps1')
c = p.read_text(encoding='utf-8')

old_frag = '''function Test-AuthorizedKeyFragment {
    param(
        [string]$Path,
        [string]$PubFragment
    )
    if (-not $PubFragment -or -not (Test-Path $Path)) { return $false }
    $pattern = [regex]::Escape($PubFragment)
    return [bool](Select-String -Path $Path -Pattern $pattern -Quiet -ErrorAction SilentlyContinue)
}
'''

new_frag = '''function Test-AuthorizedKeyFragment {
    param(
        [string]$Path,
        [string]$PubFragment
    )
    # Returns: $true / $false / $null (= unreadable; do NOT treat as missing).
    if (-not $PubFragment -or -not (Test-Path $Path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $Path -ErrorAction Stop
        $pattern = [regex]::Escape($PubFragment)
        return [bool]($raw | Where-Object { $_ -match $pattern })
    } catch {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("LAPTOP_SSH: cannot_read_ak path=$Path err=$($_.Exception.Message)") 'WARN'
        }
        return $null
    }
}
'''

if old_frag not in c:
    raise SystemExit('Test-AuthorizedKeyFragment not found')
c = c.replace(old_frag, new_frag, 1)

old_ready = '''        if ($userIsAdmin -and (Test-Path $adminDir)) {
            if (-not (Test-AuthorizedKeyFragment -Path $adminAk -PubFragment $PubFragment)) {
                $reasons.Add('Server laptop key not in administrators_authorized_keys (Windows admin user)')
            }
'''

# Need exact rest of block - read it
idx = c.find('if ($userIsAdmin -and (Test-Path $adminDir))')
print(repr(c[idx:idx+450]))
