from pathlib import Path
root = Path(__file__).resolve().parents[2]
ps = root / "scripts/client/git-mode.ps1"
lines = ps.read_text(encoding="utf-8").splitlines(keepends=True)
start = next(i for i, l in enumerate(lines) if l.startswith("function Push-RemoteUserFileIfChanged"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("function Push-LaptopExecBundleIfChanged"))
new = '''function Push-RemoteUserFileIfChanged {
    param(
        [Parameter(Mandatory)][string]$LocalSrc,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Alias,
        [switch]$Executable
    )
    if (-not (Test-Path $LocalSrc)) { return }
    $localHash = (Get-FileHash -Algorithm SHA256 -Path $LocalSrc).Hash
    # Quoted '~' does not expand on remote — use $HOME for ssh cmds; keep ~/ for scp.
    $rpath = $RemotePath
    if ($RemotePath.StartsWith('~/')) { $rpath = '$HOME/' + $RemotePath.Substring(2) }
    elseif ($RemotePath -eq '~') { $rpath = '$HOME' }
    $remoteHash = ((SshX "sha256sum $rpath 2>/dev/null | awk '{print `$1}'") -join '').Trim()
    if ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower())) { return }
    SshX ('mkdir -p "$(dirname ' + $rpath + ')"') 2>$null | Out-Null
    scp -o BatchMode=yes -o ConnectTimeout=20 -q $LocalSrc "${Alias}:$RemotePath" 2>$null
    if ($Executable -and $LASTEXITCODE -eq 0) {
        SshX ("chmod +x $rpath") 2>$null | Out-Null
    }
}

'''
text = "".join(lines[:start]) + new + "".join(lines[end:])
text = text.replace(
    "SshX '~/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>$null | Out-Null",
    "SshX '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>$null | Out-Null",
    1,
)
ps.write_text(text, encoding="utf-8", newline="\n")
print("ps patched ok")
