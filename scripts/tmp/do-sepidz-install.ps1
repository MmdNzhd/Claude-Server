Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Server = 'sepidz@192.168.250.70'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runner = Join-Path $PSScriptRoot 'sepidz-run-install.sh'
$install = Join-Path $ProjectRoot 'scripts\server\commands\install-client-bundle.sh'

Write-Host "Deploy to $Server ..." -ForegroundColor Cyan
& ssh -o BatchMode=yes -o ConnectTimeout=15 $Server 'mkdir -p ~/claude-client-bundle-deploy'

# Rebuild zip with forward slashes if needed
$zip = Join-Path $env:TEMP 'claude-sepidz-bundle-final.zip'
$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$sepidClient = Join-Path (Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1).FullName 'claude-code'
$stage = Join-Path $env:TEMP 'claude-sepidz-final-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage, (Join-Path $stage 'mac'), (Join-Path $stage 'server') | Out-Null
$win = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
$mac = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh')
foreach ($n in $win) { Copy-Item (Join-Path $sepidClient "windows\$n") (Join-Path $stage $n) -Force }
foreach ($n in $mac) { Copy-Item (Join-Path $sepidClient "mac\$n") (Join-Path $stage "mac\$n") -Force }
foreach ($rel in @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')) {
    $dst = Join-Path $stage ('server\' + ($rel -replace '/','\'))
    $parent = Split-Path $dst -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item (Join-Path $ProjectRoot "scripts\server\$($rel -replace '/','\')") $dst -Force
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zip) { Remove-Item $zip -Force }
$z = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
    $e = $z.CreateEntry($rel)
    $s = $e.Open()
    try { [System.IO.File]::OpenRead($_.FullName).CopyTo($s) } finally { $s.Dispose() }
}
$z.Dispose()

& scp -o BatchMode=yes -o ConnectTimeout=30 -q $zip "${Server}:~/claude-client-bundle-deploy/bundle.zip"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $install "${Server}:~/claude-client-bundle-deploy/install-client-bundle.sh"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $runner "${Server}:~/claude-client-bundle-deploy/run-install.sh"
& ssh -o BatchMode=yes -o ConnectTimeout=120 $Server 'chmod +x ~/claude-client-bundle-deploy/run-install.sh && bash ~/claude-client-bundle-deploy/run-install.sh'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$ver = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
$ip = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server "grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 | head -1").Trim()
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server 'bash -n /usr/local/share/claude-client/mac/claude-mount.sh && rm -f ~/claude-client-bundle-deploy/run-install.sh && echo mount=OK'
Write-Host "OK Sepidz v$ver ip=$ip" -ForegroundColor Green
