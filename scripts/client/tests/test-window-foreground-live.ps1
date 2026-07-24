# test-window-foreground-live.ps1 - Bug 10 LIVE: proves Set-CursorWindowForeground (the
# AttachThreadInput-based fix for the launched/detected Cursor window never becoming the
# foreground window, since Windows denies SetForegroundWindow rights by default to windows
# opened by a background process such as the b394340 "LIMITED" Scheduled Task launch path)
# actually moves real foreground focus to a real, minimized, non-foreground window - using
# real GetForegroundWindow() queries, not a source-text check.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Cursor window foreground-forcing (Bug 10) LIVE ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
foreach ($n in @('Write-EditorLaunchLog', 'Initialize-Win32WindowEnum', 'Set-CursorWindowForeground')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}
Assert $true 'extracted real Set-CursorWindowForeground (and Initialize-Win32WindowEnum) verbatim from editor-launch.ps1'

# Compile a real, tiny classic-Win32 WinForms decoy (NOT notepad.exe/calc.exe - on modern
# Windows those are UWP-packaged and their visible window is actually owned by a separate
# ApplicationFrameHost.exe container process, so Process.MainWindowHandle on the launched
# process never populates - a known OS quirk, not a real repro of "a background process's own
# window"). A self-compiled WinForms exe is a real, directly-owned classic top-level window,
# a faithful stand-in for Cursor.exe's own real window.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-fg-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$decoyExe = Join-Path $tmp 'ForegroundDecoy.exe'
$decoySrc = @'
using System;
using System.Windows.Forms;
class ForegroundDecoy {
    [STAThread]
    static void Main() {
        Form f = new Form();
        f.Text = "ForegroundDecoyWindow";
        f.Width = 300; f.Height = 200;
        f.Show();
        Application.Run(f);
    }
}
'@
try {
    Add-Type -Language CSharp -TypeDefinition $decoySrc -OutputType WindowsApplication -OutputAssembly $decoyExe `
        -ReferencedAssemblies 'System.Windows.Forms.dll', 'System.Drawing.dll' -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile decoy WinForms exe: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Assert (Test-Path -LiteralPath $decoyExe) 'decoy WinForms exe compiled to a real binary'

$notepad = $null
try {
    $notepad = Start-Process -FilePath $decoyExe -PassThru
    $hwnd = [IntPtr]::Zero
    for ($i = 0; $i -lt 40 -and $hwnd -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 150
        $notepad.Refresh()
        $hwnd = $notepad.MainWindowHandle
    }
    Assert ($hwnd -ne [IntPtr]::Zero) "real decoy process produced a real top-level window handle (hwnd=$hwnd)"

    Initialize-Win32WindowEnum
    # Minimize the decoy and shift real OS foreground focus elsewhere (this console/PowerShell
    # process itself) so the decoy starts from a genuine non-foreground, minimized state - the
    # exact starting condition a background-launched Cursor window is in.
    [void][ClaudeConnectWin32Window]::ShowWindow($hwnd, 6)  # SW_MINIMIZE
    Start-Sleep -Milliseconds 400
    $isIconicBefore = [bool][ClaudeConnectWin32Window]::IsIconic($hwnd)
    Assert $isIconicBefore 'decoy window is really minimized before the fix runs (real IsIconic check)'
    $fgBefore = [ClaudeConnectWin32Window]::GetForegroundWindow()
    Assert ($fgBefore -ne $hwnd) 'decoy window is NOT the real foreground window before the fix runs (real GetForegroundWindow check)'

    $ok = Set-CursorWindowForeground -Hwnd $hwnd
    Assert ($ok -eq $true) 'Set-CursorWindowForeground reports success (real SetForegroundWindow call returned true)'
    Start-Sleep -Milliseconds 300

    $isIconicAfter = [bool][ClaudeConnectWin32Window]::IsIconic($hwnd)
    Assert (-not $isIconicAfter) 'FIXED: decoy window is no longer minimized after the fix (real ShowWindow/SW_RESTORE took effect)'
    $fgAfter = [ClaudeConnectWin32Window]::GetForegroundWindow()
    Assert ($fgAfter -eq $hwnd) 'FIXED: decoy window IS NOW the real OS foreground window (real GetForegroundWindow check) - this is what production could not do before Bug 10 was fixed'
} finally {
    if ($notepad) {
        try {
            $stillAlive = Get-Process -Id $notepad.Id -ErrorAction SilentlyContinue
            if ($stillAlive) { Stop-Process -Id $notepad.Id -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    Start-Sleep -Milliseconds 300
    $gone = $true
    if ($notepad) { $gone = -not (Get-Process -Id $notepad.Id -ErrorAction SilentlyContinue) }
    Assert $gone 'decoy process PID confirmed gone after the run (cleaned up in finally)'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): Bug 10 is FIXED - a real, minimized, non-foreground window is genuinely brought to the OS foreground by the fix.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
