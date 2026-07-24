# test-remote-editor-detect-live.ps1 - LIVE: proves the real editor-on-folder detection
# logic in editor-launch.ps1 (Invoke-CimEditorProcessQuery / Test-PathNeedleBoundaryMatch /
# Get-RemoteEditorProcesses / Test-RemoteEditorOnCorrectFolder) correctly identifies a REAL
# spawned decoy process as "on the correct folder" (true positive) and correctly rejects a
# similarly-shaped but boundary-violating decoy (true negative) - using real Win32_Process
# enumeration via Get-CimInstance, not a source-text check.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Remote editor on-folder detection (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
foreach ($n in @(
    'Test-LaunchPerfEnabled', 'Write-LaunchPerfLog', 'Write-EditorLaunchLog',
    'Invoke-CimEditorProcessQuery', 'Invoke-CimCursorProcessQuery',
    'Get-CursorProfileProcesses', 'Test-PathNeedleBoundaryMatch',
    'Get-RemoteEditorProcesses', 'Get-CursorMainProfileProcesses',
    'Test-CursorWindowTitleIsAgentHome', 'Test-CursorWindowShowsAgentHome',
    'Test-RemoteEditorInAgentHome', 'Get-RemoteFolderUri',
    'Test-RemoteEditorOnCorrectFolder', 'Get-RemoteEditorSessionPresence', 'Clear-CursorProcessCache'
)) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Stub the profile-dir resolver to a fake test path so this test never touches the real
# shared golden Cursor profile (ClaudeServerCursorProfile-Smart/-Sepidz).
$script:FakeProfileDir = $null
function Get-CursorRemoteProfileDir { return $script:FakeProfileDir }
function Get-CodeRemoteProfileDir { return $null }

$script:EditorCimCache = @{}
$script:EditorCimCacheTtlSec = 2
$script:LaunchCimCallCount = 0

$Alias = 'unit-test-alias'
$TargetPath = '/home/testuser/test-project'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-editor-detect-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$script:FakeProfileDir = Join-Path $tmp 'FakeCursorProfile'
New-Item -ItemType Directory -Force -Path $script:FakeProfileDir | Out-Null

$stubExe = Join-Path $tmp 'Cursor.exe'
$stubSrc = @'
using System.Threading;
class RemoteEditorDetectStub { static void Main(string[] args) { Thread.Sleep(Timeout.Infinite); } }
'@
try {
    Add-Type -Language CSharp -TypeDefinition $stubSrc -OutputType ConsoleApplication -OutputAssembly $stubExe -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile decoy Cursor.exe: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Assert (Test-Path -LiteralPath $stubExe) 'decoy hang-forever Cursor.exe compiled to a real binary (Name=Cursor.exe matches the CIM filter this code uses)'

# Decoy #1 (true positive): realistic --folder-uri="vscode-remote://ssh-remote+<alias>/<path>"
# (quoted, as real folder-uri values are) ending exactly at the target path - satisfies both the
# exact-uri check and the boundary check (the closing '"' is a valid boundary character).
$args1 = "--user-data-dir=`"$($script:FakeProfileDir)`" --folder-uri=`"vscode-remote://ssh-remote+$Alias$TargetPath`""

# Decoy #2 (true negative): a SIBLING project whose remote path is the target path plus a
# suffix ("...test-project-sibling"). A naive substring/-match test would wrongly treat this
# as the target folder because the target path is a strict PREFIX of the decoy's path - this
# is exactly the "ai-gap vs ai-gap-summay" collision Test-PathNeedleBoundaryMatch's own source
# comment calls out. The real boundary check requires the needle be followed by one of
# \ / " ' or end-of-string; here it is followed by "-", so it must be rejected.
$args2 = "--user-data-dir=`"$($script:FakeProfileDir)`" --folder-uri=`"vscode-remote://ssh-remote+$Alias$TargetPath-sibling`""

$p1 = $null
$p2 = $null
try {
    $p1 = Start-Process -FilePath $stubExe -ArgumentList $args1 -PassThru -WindowStyle Hidden
    $p2 = Start-Process -FilePath $stubExe -ArgumentList $args2 -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 600
    Assert (-not $p1.HasExited) 'decoy #1 (true-positive candidate) is actually running'
    Assert (-not $p2.HasExited) 'decoy #2 (sibling / boundary-violating candidate) is actually running'

    $cim1 = Get-CimInstance Win32_Process -Filter "ProcessId=$($p1.Id)" -Property CommandLine -ErrorAction SilentlyContinue
    $cim2 = Get-CimInstance Win32_Process -Filter "ProcessId=$($p2.Id)" -Property CommandLine -ErrorAction SilentlyContinue
    Assert ($cim1 -and $cim1.CommandLine -match [regex]::Escape($TargetPath)) 'real Win32_Process CommandLine for decoy #1 actually contains the target path needle'
    Assert ($cim2 -and $cim2.CommandLine -match [regex]::Escape($TargetPath)) 'real Win32_Process CommandLine for decoy #2 also contains the target path as a raw substring (the naive-substring trap)'

    $pathNeedleEsc = [regex]::Escape($TargetPath)
    $boundary1 = Test-PathNeedleBoundaryMatch -CommandLine $cim1.CommandLine -NeedleEscaped $pathNeedleEsc
    $boundary2 = Test-PathNeedleBoundaryMatch -CommandLine $cim2.CommandLine -NeedleEscaped $pathNeedleEsc
    Assert ($boundary1 -eq $true) 'Test-PathNeedleBoundaryMatch ACCEPTS decoy #1 (needle followed by closing quote, a valid boundary)'
    Assert ($boundary2 -eq $false) 'Test-PathNeedleBoundaryMatch REJECTS decoy #2 (needle followed by "-", not in [\/"''] or end-of-string - the exact collision the boundary check exists to prevent)'

    $matched = @(Get-RemoteEditorProcesses -EditorCmd 'cursor' -Alias $Alias -RemotePath $TargetPath -ForceRefresh)
    $matchedIds = @($matched | ForEach-Object { $_.ProcessId })
    Assert ($matchedIds -contains $p1.Id) 'Get-RemoteEditorProcesses (real Win32_Process query) DETECTS decoy #1 as a remote editor process for the target alias+path'
    Assert (-not ($matchedIds -contains $p2.Id)) 'Get-RemoteEditorProcesses correctly EXCLUDES decoy #2 (sibling path) even though it shares alias + path prefix'

    $onFolderBoth = Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $Alias -RemotePath $TargetPath
    Assert ($onFolderBoth -eq $true) 'Test-RemoteEditorOnCorrectFolder returns TRUE (on correct folder) while the real matching decoy #1 process is running'

    try { $p1.Kill() } catch { }
    try { [void]$p1.WaitForExit(3000) } catch { }
    Start-Sleep -Milliseconds 300
    Clear-CursorProcessCache

    $onFolderOnlySibling = Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $Alias -RemotePath $TargetPath
    Assert ($onFolderOnlySibling -eq $false) 'Test-RemoteEditorOnCorrectFolder returns FALSE with ONLY the boundary-violating sibling decoy running (exact-uri check now boundary-checked too)'

    $presenceOnlySibling = Get-RemoteEditorSessionPresence -EditorCmd 'cursor' -Alias $Alias -RemotePath $TargetPath
    Assert ($presenceOnlySibling.OnFolder -eq $false) 'Get-RemoteEditorSessionPresence.OnFolder is FALSE with ONLY the sibling decoy running (same exact-uri boundary fix)'
} finally {
    foreach ($p in @($p1, $p2)) {
        if ($p) {
            try {
                $stillAlive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
                if ($stillAlive) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
    }
    Start-Sleep -Milliseconds 300
    $p1Gone = $true
    $p2Gone = $true
    if ($p1) { $p1Gone = -not (Get-Process -Id $p1.Id -ErrorAction SilentlyContinue) }
    if ($p2) { $p2Gone = -not (Get-Process -Id $p2.Id -ErrorAction SilentlyContinue) }
    Assert $p1Gone 'decoy #1 PID is confirmed gone after the run (cleaned up in finally)'
    Assert $p2Gone 'decoy #2 PID is confirmed gone after the run (cleaned up in finally)'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
