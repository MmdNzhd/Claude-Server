$ErrorActionPreference='Continue'
function NormHash([byte[]]$b){
  # strip UTF8 BOM
  if($b.Length -ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF){ $b=$b[3..($b.Length-1)] }
  # CRLF -> LF
  $text=[Text.Encoding]::UTF8.GetString($b) -replace "`r`n","`n" -replace "`r","`n"
  $bytes=[Text.Encoding]::UTF8.GetBytes($text)
  return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','')
}
function Get-RemoteBytes([string]$rel){
  $out=Join-Path $env:TEMP ('rb-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.bin')
  # use ssh cat and write raw - careful with binary. For text files OK.
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','smart@192.168.250.70',"cat /usr/local/share/claude-client/$rel") -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.e')
  if(-not $p.WaitForExit(20000)){ try{$p.Kill()}catch{}; return $null }
  if(-not (Test-Path $out)){ return $null }
  return [IO.File]::ReadAllBytes($out)
}

$pkgWin=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows'
$fail=0
foreach($name in @('connect-version.txt','connect-update.ps1','connect.bat','git-mode.ps1','connect-ui.ps1','connect.ps1','editor-launch.ps1')){
  $pkg=[IO.File]::ReadAllBytes((Join-Path $pkgWin $name))
  $rem=Get-RemoteBytes $name
  if($null -eq $rem){ Write-Host "BAD scp/cat $name"; $fail++; continue }
  $hp=NormHash $pkg; $hr=NormHash $rem
  $rawEqual = ((Get-FileHash -InputStream ([IO.MemoryStream]::new($pkg))).Hash -eq (Get-FileHash -InputStream ([IO.MemoryStream]::new($rem))).Hash)
  # simpler raw
  $rawEqual = ($pkg.Length -eq $rem.Length)
  if($pkg.Length -eq $rem.Length){
    $same=$true; for($i=0;$i -lt $pkg.Length;$i++){ if($pkg[$i]-ne $rem[$i]){ $same=$false; break } }
    $rawEqual=$same
  } else { $rawEqual=$false }

  if($hp -eq $hr){
    if($rawEqual){ Write-Host "OK  $name identical" -ForegroundColor Green }
    else { Write-Host "OK  $name identical after CRLF/BOM normalize (line endings only)" -ForegroundColor Green }
  } else {
    Write-Host "BAD $name CONTENT DIFF even normalized" -ForegroundColor Red
    $fail++
    # show small text diff hint
    $tp=[Text.Encoding]::UTF8.GetString($pkg) -replace "`r`n","`n"
    $tr=[Text.Encoding]::UTF8.GetString($rem) -replace "`r`n","`n"
    if($name -eq 'connect-version.txt'){ Write-Host "  pkg=[$tp] rem=[$tr]" }
    else {
      Write-Host ("  sizes norm pkg=$($tp.Length) rem=$($tr.Length) raw pkg=$($pkg.Length) rem=$($rem.Length)")
      # first line diff
      $lp=$tp -split "`n"; $lr=$tr -split "`n"
      $max=[Math]::Min($lp.Count,$lr.Count)
      $diffs=0
      for($i=0;$i -lt $max -and $diffs -lt 5;$i++){
        if($lp[$i] -ne $lr[$i]){ Write-Host ("  L$($i+1) pkg=$($lp[$i].Substring(0,[Math]::Min(100,$lp[$i].Length)))"); Write-Host ("  L$($i+1) rem=$($lr[$i].Substring(0,[Math]::Min(100,$lr[$i].Length)))"); $diffs++ }
      }
      if($lp.Count -ne $lr.Count){ Write-Host "  linecount pkg=$($lp.Count) rem=$($lr.Count)" }
    }
  }
}
Write-Host ''
Write-Host "fail=$fail"
exit $fail
