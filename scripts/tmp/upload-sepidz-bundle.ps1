Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$sepidClient = Join-Path (Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1).FullName 'claude-code'
$RemoteDeployDir = 'claude-client-bundle-deploy'
$Server = 'smart@192.168.250.70'

$WinBundleFiles = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
$MacBundleFiles = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh')
$ServerBundleFiles = @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')

function Copy-EnsureDir($Src, $Dst) {
    $parent = Split-Path $Dst -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

function New-BundleZipFromDirectory {
    param([string]$SourceDir, [string]$ZipPath)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -Path $SourceDir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($SourceDir.Length).TrimStart('\')
            $entry = $zip.CreateEntry($rel.Replace('\', '/'))
            $stream = $entry.Open()
            try {
                $fs = [System.IO.File]::Open($_.FullName, 'Open', 'Read', 'ReadWrite')
                try { $fs.CopyTo($stream) } finally { $fs.Dispose() }
            } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
}

$stage = Join-Path $env:TEMP 'claude-sepidz-bundle-stage'
$zip = Join-Path $env:TEMP 'claude-sepidz-bundle.zip'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage, (Join-Path $stage 'mac') | Out-Null
foreach ($n in $WinBundleFiles) { Copy-EnsureDir (Join-Path $sepidClient "windows\$n") (Join-Path $stage $n) }
foreach ($n in $MacBundleFiles) { Copy-EnsureDir (Join-Path $sepidClient "mac\$n") (Join-Path $stage "mac\$n") }
foreach ($rel in $ServerBundleFiles) {
    Copy-EnsureDir (Join-Path $ProjectRoot ("scripts\server\" + ($rel -replace '/','\'))) (Join-Path $stage ("server\" + ($rel -replace '/','\')))
}

New-BundleZipFromDirectory -SourceDir $stage -ZipPath $zip

$installScript = Join-Path $ProjectRoot 'scripts\server\commands\install-client-bundle.sh'
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server "mkdir -p ~/$RemoteDeployDir"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $zip "${Server}:~/$RemoteDeployDir/bundle.zip"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $installScript "${Server}:~/$RemoteDeployDir/install-client-bundle.sh"
Write-Host "Uploaded Sepidz bundle v$((Get-Content (Join-Path $sepidClient 'windows\connect-version.txt') -Raw).Trim()) with forward-slash zip paths" -ForegroundColor Green
Write-Host "Run from laptop terminal (sudo password required):" -ForegroundColor Yellow
Write-Host "  ssh -t smart@192.168.250.70 `"chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh && sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip`"" -ForegroundColor Cyan
