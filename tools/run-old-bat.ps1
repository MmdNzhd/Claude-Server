$batDir='C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$out=Join-Path $env:TEMP 'old-bat-out.txt'
$err=Join-Path $env:TEMP 'old-bat-err.txt'
Remove-Item $out,$err -Force -EA SilentlyContinue
$p=Start-Process -FilePath 'cmd.exe' -WorkingDirectory $batDir -ArgumentList @('/c','connect.bat') -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
Write-Host ("exit={0}" -f $p.ExitCode)
Write-Host '--- stdout ---'
if (Test-Path $out) { Get-Content $out -Tail 40 }
Write-Host '--- stderr ---'
if (Test-Path $err) { Get-Content $err -Tail 40 }
Write-Host '--- folder ---'
Get-ChildItem $batDir -Name
Write-Host ("exe={0}" -f (Get-Item (Join-Path $batDir 'Claude-Connect.exe') -EA SilentlyContinue).Length)
