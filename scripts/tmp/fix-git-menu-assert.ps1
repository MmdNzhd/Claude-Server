$path='D:\Smart\Claude-Code-Server\scripts\client\tests\test-connect-pipeline.ps1'
$c=Get-Content $path -Raw
$old='Assert ($src -match ''"g" \{ Configure-GitMode \}'') "$rel has git menu option"'
$new='Assert ($src -match ''"g" \{.*Configure-GitMode'') "$rel has git menu option"'
if($c -notlike "*$old*"){ throw "pattern not found" }
$c2=$c.Replace($old,$new)
[System.IO.File]::WriteAllText($path,$c2)
Write-Output 'patched test assert'
