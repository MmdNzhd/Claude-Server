$ErrorActionPreference='Continue'
$pkgRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code'
$pkgWin = Join-Path $pkgRoot 'windows'

Write-Host '=== editor-launch SHA why ==='
$a=Get-FileHash 'scripts\client\editor-launch.ps1' -Algorithm SHA256
$b=Get-FileHash (Join-Path $pkgWin 'editor-launch.ps1') -Algorithm SHA256
Write-Host ("src=$($a.Hash) size=$((Get-Item scripts\client\editor-launch.ps1).Length)")
Write-Host ("pkg=$($b.Hash) size=$((Get-Item (Join-Path $pkgWin 'editor-launch.ps1')).Length)")
# compare first differing bytes
$sb=[IO.File]::ReadAllBytes((Resolve-Path 'scripts\client\editor-launch.ps1'))
$pb=[IO.File]::ReadAllBytes((Join-Path $pkgWin 'editor-launch.ps1'))
Write-Host ("len src=$($sb.Length) pkg=$($pb.Length)")
$min=[Math]::Min($sb.Length,$pb.Length)
for($i=0;$i -lt $min;$i++){ if($sb[$i] -ne $pb[$i]){ Write-Host ("first_diff_at=$i src=$($sb[$i]) pkg=$($pb[$i])"); break } }
if($sb.Length -ne $pb.Length -and $min -eq [Math]::Min($sb.Length,$pb.Length)){
  # check BOM
  Write-Host ("src_bom={0:X2}{1:X2}{2:X2}" -f $sb[0],$sb[1],$sb[2])
  Write-Host ("pkg_bom={0:X2}{1:X2}{2:X2}" -f $pb[0],$pb[1],$pb[2])
}
# mtimes
Write-Host ("src_mtime=$((Get-Item scripts\client\editor-launch.ps1).LastWriteTime)")
Write-Host ("pkg_mtime=$((Get-Item (Join-Path $pkgWin 'editor-launch.ps1')).LastWriteTime)")

Write-Host ''
Write-Host '=== remote scp as smart@250.70 (actual connect user) ==='
$tmpdir=Join-Path $env:TEMP ('deep2-' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Force -Path $tmpdir | Out-Null
$fail=0
foreach($rf in @('connect-version.txt','connect-update.ps1','git-mode.ps1','connect-ui.ps1','connect.ps1','connect.bat','editor-launch.ps1')){
  $local=Join-Path $tmpdir $rf
  $err=$local+'.e'
  $p=Start-Process scp -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q',"smart@192.168.250.70:/usr/local/share/claude-client/$rf",$local) -NoNewWindow -PassThru -RedirectStandardOutput ($local+'.o') -RedirectStandardError $err
  if(-not $p.WaitForExit(30000)){ Write-Host "TIMEOUT $rf"; $fail++; continue }
  $e=((Get-Content $err -Raw -EA SilentlyContinue)+'').Trim()
  if($p.ExitCode -ne 0 -or -not (Test-Path $local)){ Write-Host "FAIL $rf exit=$($p.ExitCode) err=$e"; $fail++; continue }
  $pkgFile=Join-Path $pkgWin $rf
  $h1=(Get-FileHash $pkgFile).Hash
  $h2=(Get-FileHash $local).Hash
  if($h1 -eq $h2){ Write-Host "OK remote==pkg $rf" -ForegroundColor Green }
  else {
    Write-Host "DIFF remote!=pkg $rf" -ForegroundColor Yellow
    # show if only newline or BOM
    $x=[IO.File]::ReadAllBytes($pkgFile); $y=[IO.File]::ReadAllBytes($local)
    Write-Host ("  sizes pkg=$($x.Length) rem=$($y.Length)")
  }
}
Write-Host ''
Write-Host '=== sepidz@ why scp failed ==='
$err2=Join-Path $env:TEMP 'scp-sepidz.err'
$p2=Start-Process scp -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','-q','sepidz@192.168.250.70:/usr/local/share/claude-client/connect-version.txt',(Join-Path $tmpdir 'via-sepidz.txt')) -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\scp-s.o') -RedirectStandardError $err2
$null=$p2.WaitForExit(15000)
Write-Host ("sepidz_scp_exit=$($p2.ExitCode) err="+((Get-Content $err2 -Raw -EA SilentlyContinue)+'').Trim())

# ls perms
$cmd='ls -la /usr/local/share/claude-client/connect-update.ps1 connect-version.txt 2>&1; id; namei /usr/local/share/claude-client/connect-update.ps1 2>&1 | tail -5'
$o=Join-Path $env:TEMP 'perms.txt'
foreach($user in @('sepidz@192.168.250.70','smart@192.168.250.70')){
  Write-Host "--- $user ---"
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$user,$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
  $null=$p.WaitForExit(12000)
  Get-Content $o -EA SilentlyContinue
}

Write-Host ''
Write-Host '=== remote connect-update header + retry (via smart) ==='
$cmd2='sed -n "175,210p" /usr/local/share/claude-client/connect-update.ps1; echo ====; grep -n "attempt -le 3\|Invoke-BundleDownloadfunction\|skip_duplicate\|ControlMaster=auto" /usr/local/share/claude-client/connect-update.ps1 /usr/local/share/claude-client/git-mode.ps1 /usr/local/share/claude-client/connect.ps1 2>/dev/null'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','smart@192.168.250.70',$cmd2) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
$null=$p.WaitForExit(15000)
Get-Content $o
