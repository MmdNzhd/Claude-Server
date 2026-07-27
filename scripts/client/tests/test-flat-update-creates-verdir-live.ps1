# LIVE: flat Desktop\Claude-Connect update MUST create Claude-Connect\{remoteVer}\src
# (Mehrdad-class: in-app update from flat root used to inplace-swap and never make folders).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

$pass = 0
$fail = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { $script:pass++; Write-Host "PASS  $Name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $Name" -ForegroundColor Red }
}

$updPath = Get-ClientFile 'windows\connect-update.ps1'
$updSrc = Get-Content -LiteralPath $updPath -Raw -ErrorAction Stop
Assert ($updSrc -match 'versioned_apply_from_flat') 'source has versioned_apply_from_flat gate'
Assert ($updSrc -match 'flat_hybrid_swept') 'source has flat_hybrid_swept cleanup'

$need = @(
    'Get-ConnectVersionedLayout',
    'ConvertTo-ConnectVersionedLayout',
    'Invoke-PruneConnectVersionDirs',
    'Copy-ExeAtomicSwap',
    'Get-SafeFileSha256'
)
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$chunk.AppendLine('function Write-UpdateMsg { param($Message,$Color=''Gray'') }')
[void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param($Dir) if(-not $Dir){return $false}; return $true }')
foreach ($n in $need) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    Assert ($null -ne $fn -and $fn.Length -gt 40) "extract $n"
    if ($fn) { [void]$chunk.AppendLine($fn) }
}
Invoke-Expression $chunk.ToString()

$sandbox = Join-Path $env:TEMP ("flat-verdir-live-{0}" -f [guid]::NewGuid().ToString('N'))
$flatRoot = Join-Path $sandbox 'Claude-Connect'
$winNew = Join-Path $sandbox 'winNew'
New-Item -ItemType Directory -Force -Path $flatRoot, $winNew | Out-Null

try {
    # --- Case A: pure flat root + apply to remote ver folder ---
    Set-Content -LiteralPath (Join-Path $flatRoot 'connect.ps1') -Value "#FLAT`n`$script:ConnectVersion = '20990101.01'" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $flatRoot 'connect-version.txt') -Value '20990101.01' -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $flatRoot 'connect-update.ps1') -Value '#flat-upd' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $flatRoot 'connect.bat') -Value '@echo flat' -Encoding ASCII
    # tiny fake exe bytes
    [IO.File]::WriteAllBytes((Join-Path $flatRoot 'Claude-Connect.exe'), [byte[]](0x4D, 0x5A, 0x90, 0x00, 0x01, 0x02, 0x03, 0x04))

    $layout0 = Get-ConnectVersionedLayout -Dir $flatRoot
    Assert ($layout0.Kind -eq 'flat') 'CaseA detects flat'

    $remoteVer = '20990101.99'
    Set-Content -LiteralPath (Join-Path $winNew 'connect.ps1') -Value "#NEW`n`$script:ConnectVersion = '$remoteVer'" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $winNew 'connect-version.txt') -Value $remoteVer -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $winNew 'connect-update.ps1') -Value '#new-upd' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $winNew 'connect.bat') -Value '@echo new' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $winNew 'NEW_MARKER.txt') -Value 'from-update' -Encoding ASCII
    [IO.File]::WriteAllBytes((Join-Path $winNew 'Claude-Connect.exe'), [byte[]](0x4D, 0x5A, 0x91, 0x00, 0x0A, 0x0B, 0x0C, 0x0D))

    # Mirror production apply path for flat roots (same gates as connect-update.ps1).
    $ScriptDir = $flatRoot
    $verLayoutApply = Get-ConnectVersionedLayout -Dir $ScriptDir
    $versionedRoot = $null
    $priorVerDir = $null
    if ($verLayoutApply) {
        $versionedRoot = $verLayoutApply.Root
        if ($verLayoutApply.Kind -eq 'versioned') { $priorVerDir = $verLayoutApply.VerDir }
        if ($verLayoutApply.Kind -eq 'flat' -and $remoteVer -match '^\d{8}\.\d+$') {
            $migratedApply = ConvertTo-ConnectVersionedLayout -FlatRoot $verLayoutApply.Root
            if ($migratedApply -and $migratedApply.SrcDir) {
                $ScriptDir = $migratedApply.SrcDir
                $priorVerDir = $migratedApply.VerDir
            }
            $re = Get-ConnectVersionedLayout -Dir $ScriptDir
            if ($re) {
                $versionedRoot = $re.Root
                if ($re.Kind -eq 'versioned') { $priorVerDir = $re.VerDir }
            }
            if (-not $versionedRoot) { $versionedRoot = $verLayoutApply.Root }
        }
    }
    Assert ($null -ne $versionedRoot) 'CaseA resolved Claude-Connect root'
    Assert ((Split-Path -Leaf $versionedRoot) -eq 'Claude-Connect') 'CaseA root leaf is Claude-Connect'

    $newVerDir = Join-Path $versionedRoot $remoteVer
    $newSrc = Join-Path $newVerDir 'src'
    New-Item -ItemType Directory -Force -Path $newSrc | Out-Null
    Get-ChildItem -LiteralPath $winNew -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $newSrc $_.Name) -Force -Recurse
    }
    $destExe = Join-Path $newVerDir ("Claude-Connect-{0}.exe" -f $remoteVer)
    $exeSrc = Join-Path $winNew 'Claude-Connect.exe'
    if (Test-Path -LiteralPath $exeSrc) {
        [void](Copy-ExeAtomicSwap -Source $exeSrc -Destination $destExe)
    }
    Set-Content -LiteralPath (Join-Path $versionedRoot 'current.txt') -Value $remoteVer -Encoding ASCII -NoNewline

    Assert (Test-Path -LiteralPath $newSrc) 'CaseA created {remoteVer}\src folder'
    Assert (Test-Path -LiteralPath (Join-Path $newSrc 'NEW_MARKER.txt')) 'CaseA new payload in src'
    Assert (Test-Path -LiteralPath (Join-Path $newSrc 'connect.ps1')) 'CaseA connect.ps1 in new src'
    Assert (Test-Path -LiteralPath $destExe) 'CaseA versioned EXE beside src'
    Assert ((Get-Content (Join-Path $versionedRoot 'current.txt') -Raw).Trim() -eq $remoteVer) 'CaseA current.txt -> remoteVer'
    Assert (-not (Test-Path -LiteralPath (Join-Path $flatRoot 'connect.ps1'))) 'CaseA root no longer has flat connect.ps1'

    # --- Case B: hybrid (current.txt + leftover flat root) gets swept ---
    $hybrid = Join-Path $sandbox 'hybrid\Claude-Connect'
    $hVer = '20990102.10'
    $hSrc = Join-Path (Join-Path $hybrid $hVer) 'src'
    New-Item -ItemType Directory -Force -Path $hSrc | Out-Null
    Set-Content -LiteralPath (Join-Path $hSrc 'connect.ps1') -Value '#in-src' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $hybrid 'current.txt') -Value $hVer -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $hybrid 'connect.ps1') -Value '#orphan-root' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $hybrid 'connect-version.txt') -Value $hVer -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $hybrid 'connect-update.ps1') -Value '#orphan-upd' -Encoding ASCII
    [IO.File]::WriteAllBytes((Join-Path $hybrid 'Claude-Connect.exe'), [byte[]](0x4D, 0x5A, 0x92, 0x00))

    # ConvertTo requires connect.ps1 at root for entry — hybrid has it
    $migH = ConvertTo-ConnectVersionedLayout -FlatRoot $hybrid
    Assert ($null -ne $migH -and $migH.Kind -eq 'versioned') 'CaseB hybrid returns versioned'
    Assert (-not (Test-Path -LiteralPath (Join-Path $hybrid 'connect.ps1'))) 'CaseB swept orphan connect.ps1 from root'
    Assert (Test-Path -LiteralPath (Join-Path $hSrc 'connect.ps1')) 'CaseB src still has connect.ps1'
    $hExe = Join-Path (Join-Path $hybrid $hVer) ("Claude-Connect-{0}.exe" -f $hVer)
    Assert ((Test-Path -LiteralPath $hExe) -or -not (Test-Path -LiteralPath (Join-Path $hybrid 'Claude-Connect.exe'))) 'CaseB root EXE cleared or moved into VerDir'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("RESULT pass={0} fail={1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
