from pathlib import Path

p = Path('scripts/client/windows/connect-bootstrap.ps1')
text = p.read_text(encoding='utf-8')

func = r'''
function Clear-LegacyFolderToExeOnly {
    # Publish/unzip folders must not keep a full client tree after redirect.
    # Leave only Claude-Connect.exe (+ tiny pointer readme) so users stop opening bat there.
    param(
        [Parameter(Mandatory)][string]$Dir,
        [string]$ExeSource = ''
    )
    if ([string]::IsNullOrWhiteSpace($Dir) -or -not (Test-Path -LiteralPath $Dir)) { return }
    try {
        $canonFull = [IO.Path]::GetFullPath($Canon)
        $dirFull = [IO.Path]::GetFullPath($Dir)
        if ([string]::Equals($dirFull, $canonFull, [StringComparison]::OrdinalIgnoreCase)) { return }
    } catch {}

    $exeName = 'Claude-Connect.exe'
    $keep = @{ $exeName = $true; 'READ-ME.txt' = $true }
    Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($keep.ContainsKey($_.Name)) { return }
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-BootLog ("legacy_clean_fail name=$($_.Name) err=$($_.Exception.Message)" -replace '[\r\n]', ' ') 'WARN'
        }
    }

    $dstExe = Join-Path $Dir $exeName
    $src = $ExeSource
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        $cand = @(
            (Join-Path $Canon $exeName),
            (Join-Path $env:USERPROFILE ('Desktop\' + $exeName))
        )
        foreach ($c in $cand) {
            if (Test-Path -LiteralPath $c) { $src = $c; break }
        }
    }
    if ($src -and (Test-Path -LiteralPath $src)) {
        Copy-Item -LiteralPath $src -Destination $dstExe -Force -ErrorAction SilentlyContinue
    }

    $readme = @"
Claude Connect - do not run from this folder
===========================================
This publish/unzip folder is not the live client.

Use:
  Desktop\Claude-Connect.exe
or:
  Desktop\Claude-Connect\connect.bat
"@
    try {
        [IO.File]::WriteAllText((Join-Path $Dir 'READ-ME.txt'), ($readme -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($false))
    } catch {}
    Write-BootLog ("legacy_cleaned_to_exe dir=$Dir")
}

'''

if 'function Clear-LegacyFolderToExeOnly' not in text:
    anchor = 'function Copy-DirFiles {'
    if anchor not in text:
        raise SystemExit('Copy-DirFiles not found')
    text = text.replace(anchor, func + '\n' + anchor, 1)
    print('inserted Clear-LegacyFolderToExeOnly')
else:
    print('Clear-Legacy already present')

# Replace redirect-when-current path
old1 = '''        if ($Here -and $legacy -and -not [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)) {
            Set-Content -LiteralPath $RelaunchMarker -Value $Canon -Encoding ASCII
            Write-BootLog ("redirect legacy here=$Here") 'WARN'
            exit 2
        }'''
new1 = '''        if ($Here -and $legacy -and -not [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)) {
            Clear-LegacyFolderToExeOnly -Dir $Here
            Set-Content -LiteralPath $RelaunchMarker -Value $Canon -Encoding ASCII
            Write-BootLog ("redirect legacy here=$Here") 'WARN'
            exit 2
        }'''
if old1 in text:
    text = text.replace(old1, new1, 1)
    print('patched skip+redirect path')
else:
    print('WARN skip+redirect path not found')

# Replace healed here path - DO NOT copy full tree into Here
old2 = '''        if ($Here -and -not [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)) {
            if ($legacy -or $hereBad) {
                [void](Copy-DirFiles -Src $stage -Dst $Here)
                Set-Content -LiteralPath $RelaunchMarker -Value $Canon -Encoding ASCII
                Write-BootLog ("healed here + redirect from=$Here") 'WARN'
                exit 2
            }
        }'''
new2 = '''        if ($Here -and -not [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)) {
            if ($legacy -or $hereBad) {
                $stageExe = Join-Path $stage 'Claude-Connect.exe'
                Clear-LegacyFolderToExeOnly -Dir $Here -ExeSource $stageExe
                Set-Content -LiteralPath $RelaunchMarker -Value $Canon -Encoding ASCII
                Write-BootLog ("healed canon + cleaned legacy to EXE from=$Here") 'WARN'
                exit 2
            }
        }'''
if old2 in text:
    text = text.replace(old2, new2, 1)
    print('patched heal+redirect path')
else:
    print('WARN heal path not found')

p.write_text(text, encoding='utf-8', newline='\n')
print('bootstrap OK')
