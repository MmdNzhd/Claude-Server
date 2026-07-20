$ErrorActionPreference='Continue'
$opts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ConnectionAttempts=1','-o','ControlMaster=no','-o','StrictHostKeyChecking=accept-new','sepidz@192.168.250.70',"cat '/usr/local/share/claude-client/connect-version.txt'")
Write-Host 'ARGS:' ($opts -join ' | ')
$id=[guid]::NewGuid().ToString('N').Substring(0,8)
$outFile=Join-Path $env:TEMP "d-$id.out"
$errFile=Join-Path $env:TEMP "d-$id.err"
$p=Start-Process -FilePath ssh -ArgumentList $opts -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
Write-Host "started pid=$($p.Id)"
$ok=$p.WaitForExit(20000)
Write-Host "wait=$ok exit=$($p.ExitCode)"
Write-Host 'OUT:' ((Get-Content $outFile -Raw -EA SilentlyContinue)+'')
Write-Host 'ERR:' ((Get-Content $errFile -Raw -EA SilentlyContinue)+'')
# compare with call operator
Write-Host '=== call operator ==='
$out2 = & ssh @opts 2>&1
Write-Host "ec=$LASTEXITCODE out=$out2"
