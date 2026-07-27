#Requires -Version 5.1
# Hide the current console window if one is attached (BAT_INNER belt).
# Fail-open: never throw back into connect.bat.
$ErrorActionPreference = 'SilentlyContinue'
try {
    if (-not ('CCHide.Native' -as [type])) {
        Add-Type -Namespace CCHide -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    }
    $h = [CCHide.Native]::GetConsoleWindow()
    if ($h -ne [IntPtr]::Zero) {
        [void][CCHide.Native]::ShowWindow($h, 0) # SW_HIDE
    }
} catch { }
