from pathlib import Path

PE_FN = (
    "function Test-ConnectExePeValid {\n"
    "    param([Parameter(Mandatory)][string]$Path)\n"
    "    if (-not (Test-Path -LiteralPath $Path)) { return $false }\n"
    "    try {\n"
    "        $fs = [IO.File]::OpenRead($Path)\n"
    "        try {\n"
    "            $hdr = New-Object byte[] 64\n"
    "            if ($fs.Read($hdr, 0, 64) -lt 64) { return $false }\n"
    "            if ($hdr[0] -ne 0x4D -or $hdr[1] -ne 0x5A) { return $false }\n"
    "            $peOff = [BitConverter]::ToInt32($hdr, 0x3C)\n"
    "            if ($peOff -lt 64 -or $peOff -gt 1024) { return $false }\n"
    "            $null = $fs.Seek([int64]$peOff, [IO.SeekOrigin]::Begin)\n"
    "            $sig = New-Object byte[] 4\n"
    "            if ($fs.Read($sig, 0, 4) -ne 4) { return $false }\n"
    "            return ($sig[0] -eq 0x50 -and $sig[1] -eq 0x45 -and $sig[2] -eq 0 -and $sig[3] -eq 0)\n"
    "        } finally { $fs.Dispose() }\n"
    "    } catch { return $false }\n"
    "}\n\n"
)

u = Path("scripts/client/windows/connect-update.ps1")
t = u.read_text(encoding="utf-8")
if "function Test-ConnectExePeValid" not in t:
    t = t.replace("function Test-RemoteExePresent {", PE_FN + "function Test-RemoteExePresent {", 1)
    print("update: PE fn")
needle = '    Write-UpdateFileLog ("exe_only_scp_ok bytes=$len")'
insert = (
    "    if (-not (Test-ConnectExePeValid -Path $tmpExe)) {\n"
    '        Write-UpdateFileLog ("exe_only_pe_invalid bytes=$len") \'ERROR\'\n'
    "        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue\n"
    "        return $false\n"
    "    }\n"
    '    Write-UpdateFileLog ("exe_only_scp_ok bytes=$len pe=1")'
)
if "exe_only_pe_invalid" not in t:
    if needle not in t:
        raise SystemExit("scp_ok needle missing")
    t = t.replace(needle, insert, 1)
    print("update: pe gate")
u.write_text(t, encoding="utf-8", newline="\n")

b = Path("scripts/client/windows/connect-bootstrap.ps1")
bt = b.read_text(encoding="utf-8")
if "function Test-ConnectExePeValid" not in bt:
    bt = bt.replace("function Clear-LegacyFolderToExeOnly {", PE_FN + "function Clear-LegacyFolderToExeOnly {", 1)
    print("boot: PE fn")
old = (
    "    if ($src -and (Test-Path -LiteralPath $src)) {\n"
    "        Copy-Item -LiteralPath $src -Destination $dstExe -Force -ErrorAction SilentlyContinue\n"
    "    }"
)
new = (
    "    if ($src -and (Test-Path -LiteralPath $src) -and (Test-ConnectExePeValid -Path $src)) {\n"
    "        Copy-Item -LiteralPath $src -Destination $dstExe -Force -ErrorAction SilentlyContinue\n"
    "    } elseif (Test-Path -LiteralPath $dstExe) {\n"
    "        if (-not (Test-ConnectExePeValid -Path $dstExe)) {\n"
    "            Remove-Item -LiteralPath $dstExe -Force -ErrorAction SilentlyContinue\n"
    "            Write-BootLog 'legacy_exe_removed_invalid_pe' 'WARN'\n"
    "        }\n"
    "    }"
)
if "legacy_exe_removed_invalid_pe" not in bt:
    if old not in bt:
        raise SystemExit("legacy copy block missing")
    bt = bt.replace(old, new, 1)
    print("boot: legacy pe gate")
b.write_text(bt, encoding="utf-8", newline="\n")
print("client patches done")
