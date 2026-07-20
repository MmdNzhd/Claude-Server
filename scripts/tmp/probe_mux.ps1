$ErrorActionPreference='Continue'
$Alias='claude-server-sepidz'
Write-Host (ssh -V 2>&1 | Out-String)

function Try-Mux([string]$label, [string]$path) {
  Write-Host "--- $label path=$path"
  $args1 = @(
    '-n','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ClearAllForwardings=yes',
    '-o','ControlMaster=auto',"-o","ControlPath=$path",'-o','ControlPersist=30',
    $Alias,'echo first'
  )
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $p=Start-Process ssh -ArgumentList $args1 -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+"\mx1.out") -RedirectStandardError ($env:TEMP+"\mx1.err")
  $null=$p.WaitForExit(20000); $sw.Stop()
  $o1=((Get-Content ($env:TEMP+'\mx1.out') -Raw -EA SilentlyContinue)+'').Trim()
  $e1=((Get-Content ($env:TEMP+'\mx1.err') -Raw -EA SilentlyContinue)+'').Trim()
  Write-Host ("first ms={0} exit={1} out={2} err={3}" -f $sw.ElapsedMilliseconds,$p.ExitCode,$o1,($e1.Substring(0,[Math]::Min(120,$e1.Length))))

  $sw2=[Diagnostics.Stopwatch]::StartNew()
  $p2=Start-Process ssh -ArgumentList $args1 -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+"\mx2.out") -RedirectStandardError ($env:TEMP+"\mx2.err")
  # fix: second should say echo second
  $args2 = $args1.Clone(); $args2[-1]='echo second'
  $p2=Start-Process ssh -ArgumentList $args2 -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+"\mx2.out") -RedirectStandardError ($env:TEMP+"\mx2.err")
  $null=$p2.WaitForExit(20000); $sw2.Stop()
  $o2=((Get-Content ($env:TEMP+'\mx2.out') -Raw -EA SilentlyContinue)+'').Trim()
  Write-Host ("second ms={0} exit={1} out={2}" -f $sw2.ElapsedMilliseconds,$p2.ExitCode,$o2)

  $pe=Start-Process ssh -ArgumentList @('-O','exit',"-o","ControlPath=$path",$Alias) -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\mxE.out') -RedirectStandardError ($env:TEMP+'\mxE.err')
  $null=$pe.WaitForExit(5000)
  $ee=((Get-Content ($env:TEMP+'\mxE.err') -Raw -EA SilentlyContinue)+'').Trim()
  Write-Host ("exit_mux err={0}" -f ($ee.Substring(0,[Math]::Min(100,$ee.Length))))
}

$tmpdir = Join-Path $env:TEMP 'claude-ssh-mux'
New-Item -ItemType Directory -Force -Path $tmpdir | Out-Null
Try-Mux 'pipe' '\\.\pipe\claude-connect-probe-%C'
Try-Mux 'tempfile' (Join-Path $tmpdir 'cm-%C')
# cold baseline
$sw=[Diagnostics.Stopwatch]::StartNew()
$p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no',$Alias,'echo cold') -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\c.out') -RedirectStandardError ($env:TEMP+'\c.err')
$null=$p.WaitForExit(15000); $sw.Stop()
Write-Host ("cold_no_mux ms={0}" -f $sw.ElapsedMilliseconds)
