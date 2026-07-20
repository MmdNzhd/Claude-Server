$ErrorActionPreference = 'Continue'
$files = @(
  'scripts\client\windows\connect.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\mac\connect.sh',
  'scripts\client\connect-ui.sh'
)
$pat = 'ReadKey|VirtualKey|KeyAvailable|FlushInputBuffer|GetKeyboardLayout|Persian|VK_|Mutex|RunAs|isAdmin|DefaultAction|history|WARN|EmptyConsole|GetAsyncKeyState|FlushConsole|KeyChar|Console\.Key'
foreach ($f in $files) {
  if (-not (Test-Path $f)) { Write-Host "MISSING $f"; continue }
  Write-Host "===== $f ====="
  Select-String -Path $f -Pattern $pat -CaseSensitive:$false | Select-Object -First 80 | ForEach-Object {
    "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim()
  }
}
Write-Host '===== VERSION ====='
Get-Content scripts\client\windows\connect-version.txt
Write-Host '===== REMEMBER / NOTES ====='
Get-ChildItem .remember -Recurse -ErrorAction SilentlyContinue | Select-Object -First 30 -ExpandProperty FullName
Select-String -Path CLAUDE.md,'docs\*.md' -Pattern '20260719' -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object {
  "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(160,$_.Line.Trim().Length))
}
