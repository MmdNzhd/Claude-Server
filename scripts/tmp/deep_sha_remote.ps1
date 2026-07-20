$ErrorActionPreference='Continue'
$fail=0
function Ok($m){Write-Host "OK  $m" -ForegroundColor Green}
function Bad($m){Write-Host "BAD $m" -ForegroundColor Red; $script:fail++}
function Info($m){Write-Host "    $m" -ForegroundColor DarkGray}

$pkgWin = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows'

Write-Host '=== BOM note editor-launch ==='
# strip BOM from src and compare
$src=[IO.File]::ReadAllBytes((Resolve-Path 'scripts\client\editor-launch.ps1'))
$pkg=[IO.File]::ReadAllBytes((Join-Path $pkgWin 'editor-launch.ps1'))
if($src.Length -ge 3 -and $src[0]-eq 0xEF -and $src[1]-eq 0xBB -and $src[2]-eq 0xBF){
  $src2=$src[3..($src.Length-1)]
  $h1=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([byte[]]$src2)).Replace('-','')
  $h2=(Get-FileHash (Join-Path $pkgWin 'editor-launch.ps1')).Hash
  if($h1 -eq $h2){ Ok 'editor-launch: only BOM stripped by publish (content identical)' }
  else { Bad 'editor-launch content differs beyond BOM' }
} else { Warn 'src has no BOM?' }

Write-Host ''
Write-Host '=== remote sha256sum via smart@ (authoritative) ==='
$files='connect-version.txt connect-update.ps1 git-mode.ps1 connect-ui.ps1 connect.ps1 connect.bat editor-launch.ps1'
$cmd = "cd /usr/local/share/claude-client && sha256sum $files && echo --- && grep -n 'attempt -le 3\|Invoke-BundleDownloadfunction\|skip_duplicate\|ControlMaster=auto\|ONE SSH\|CLAUDE_CONNECT_PERF' connect-update.ps1 git-mode.ps1 connect.ps1 connect-ui.ps1 2>/dev/null | head -40"
$o=Join-Path $env:TEMP 'sha-rem.txt'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','smart@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
if(-not $p.WaitForExit(20000)){ Bad 'ssh timeout' }
else {
  $txt=Get-Content $o -Raw
  Write-Host $txt
  # parse hashes
  foreach($line in ($txt -split "`n")){
    if($line -match '^([a-f0-9]{64})\s+(\S+)$'){
      $hash=$Matches[1].ToUpper(); $name=$Matches[2]
      $pkgFile=Join-Path $pkgWin $name
      if(-not (Test-Path $pkgFile)){ Bad "pkg missing $name"; continue }
      $ph=(Get-FileHash $pkgFile).Hash
      if($ph -eq $hash){ Ok "remote==pkg $name" }
      else {
        # try BOM-stripped compare for any file
        $pb=[IO.File]::ReadAllBytes($pkgFile)
        # remote shouldn't have bom from publish
        Bad "HASH DIFF $name pkg=$($ph.Substring(0,12)) rem=$($hash.Substring(0,12))"
        Info ("pkg_size=$((Get-Item $pkgFile).Length)")
      }
    }
  }
  if($txt -match 'Invoke-BundleDownloadfunction'){ Bad 'remote still has dup header' } else { Ok 'remote no dup BundleDownload header' }
  if($txt -match 'attempt -le 3'){ Ok 'remote retry x3 present' } else { Bad 'remote retry missing' }
  if($txt -match 'skip_duplicate'){ Ok 'remote dedupe present' } else { Bad 'remote dedupe missing' }
  if($txt -match 'ControlMaster=auto'){ Bad 'remote has mux' } else { Ok 'remote no mux' }
}

Write-Host ''
Write-Host '=== local connect-update size vs remote listed 18447 ==='
Info ("local_update_size=$((Get-Item scripts\client\windows\connect-update.ps1).Length)")
Info ("pkg_update_size=$((Get-Item (Join-Path $pkgWin 'connect-update.ps1')).Length)")

Write-Host ''
Write-Host '=== Smart still frozen? ==='
$cmdS='tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt; echo; sha256sum /usr/local/share/claude-client/connect-version.txt'
$o2=Join-Path $env:TEMP 'smartv.txt'
$p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','smart@192.168.210.240',$cmdS) -NoNewWindow -PassThru -RedirectStandardOutput $o2 -RedirectStandardError ($o2+'.e')
$null=$p2.WaitForExit(12000)
$sv=((Get-Content $o2 -Raw)+'').Trim()
Info $sv
if($sv -match '20260717\.22'){ Ok 'Smart still .22' } else { Bad "Smart=$sv" }

Write-Host ''
if($fail -eq 0){ Write-Host 'LEFTOVERS RESOLVED / DEEP OK' -ForegroundColor Green } else { Write-Host "STILL FAIL=$fail" -ForegroundColor Red }
exit $fail
