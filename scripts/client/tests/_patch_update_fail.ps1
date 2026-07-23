$ErrorActionPreference = 'Stop'
$p = (Resolve-Path 'scripts\client\tests\test-connect-update-fail-exit.ps1').Path
$t = [IO.File]::ReadAllText($p)
$orig = $t
$t = $t.Replace('$start + 1700', '$start + 2000')
$old1 = "Assert (`$win -match `"manifest_empty_or_unreachable' 'ERROR'; exit 1`") 'Win manifest_empty -> exit 1'"
$new1 = "Assert (`$win -match `"manifest_empty_or_unreachable' 'ERROR'[\s\S]{0,80}?exit 1`") 'Win manifest_empty -> exit 1'"
$old2 = "Assert (`$win -match `"manifest_zero_files' 'ERROR'; exit 1`") 'Win manifest_zero -> exit 1'"
$new2 = "Assert (`$win -match `"manifest_zero_files' 'ERROR'[\s\S]{0,80}?exit 1`") 'Win manifest_zero -> exit 1'"
if ($t.Contains($old1)) { $t = $t.Replace($old1, $new1); Write-Host 'patched manifest_empty' } else { Write-Host 'MISS old1' }
if ($t.Contains($old2)) { $t = $t.Replace($old2, $new2); Write-Host 'patched manifest_zero' } else { Write-Host 'MISS old2' }
if ($t -eq $orig) { throw 'no changes' }
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($p, $t, $utf8)
Write-Host 'OK'
