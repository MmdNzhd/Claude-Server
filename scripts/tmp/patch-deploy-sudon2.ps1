$ErrorActionPreference='Stop'
$p=(Resolve-Path 'publish\deploy-client-bundles.ps1').Path
$raw=[IO.File]::ReadAllText($p)
$nl=if($raw -match "`r`n"){"`r`n"}else{"`n"}
$c=$raw -replace "`r`n","`n"
# show exact lines around installing
$lines=$c -split "`n"
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'installing\.\.\.|sudo -n bash'){
    '{0}: {1}' -f ($i+1), $lines[$i]
  }
}
# Replace sudo -n block line-by-line
$hit=$false
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'Prefer passwordless sudo'){
    # replace from this comment through sudoExit assignment before password if
    $start=$i
    # find "& ssh ... sudo -n"
    while($i -lt $lines.Count -and $lines[$i] -notmatch '\$sudoExit = \$LASTEXITCODE'){ $i++ }
    if($i -ge $lines.Count){ throw 'sudoExit line not found' }
    $end=$i
    $replacement = @(
      '    # Prefer password path when available — sudo -n over flaky SSH often hangs and never falls back.',
      '    $sudoExit = 1',
      '    if (-not $SudoPassword) {',
      '        & ssh -o BatchMode=yes -o ConnectTimeout=8 $ServerTarget "sudo -n bash ~/$RemoteDeployDir/install-client-bundle.sh ~/$RemoteDeployDir/bundle.zip" 2>$null | Out-Null',
      '        $sudoExit = $LASTEXITCODE',
      '    }'
    )
    $new = New-Object System.Collections.Generic.List[string]
    for($j=0;$j -lt $start;$j++){ $new.Add($lines[$j]) }
    foreach($r in $replacement){ $new.Add($r) }
    for($j=$end+1;$j -lt $lines.Count;$j++){ $new.Add($lines[$j]) }
    $lines = $new.ToArray()
    $hit=$true
    break
  }
}
if(-not $hit){ throw 'Prefer passwordless comment not found' }
$c2 = ($lines -join "`n")
if($nl -eq "`r`n"){ $c2 = $c2 -replace "`n","`r`n" }
[IO.File]::WriteAllText($p,$c2)
Write-Host 'OK deploy-client-bundles patched'
# confirm
Select-String -Path $p -Pattern 'Prefer password path|sudo -n' | ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
