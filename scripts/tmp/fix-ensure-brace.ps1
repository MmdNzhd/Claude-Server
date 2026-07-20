Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false
$pPath=(Resolve-Path 'scripts\client\git-mode.ps1').Path
$lines=[System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]][IO.File]::ReadAllLines($pPath))

# Fix double brace before elseif recent_success
for($i=0;$i -lt $lines.Count-1;$i++){
  if($lines[$i] -match '^\s+\}\s*$' -and $lines[$i+1] -match '^\s+\} elseif \(\$script:LastTunnelSpawnSuccessAt'){
    # merge: remove line i, change i+1 to } elseif
    $lines[$i+1]=($lines[$i+1] -replace '^\s+\} elseif','        } elseif')
    $lines.RemoveAt($i)
    'merged ensure elseif'
    break
  }
}

[IO.File]::WriteAllLines($pPath,$lines.ToArray(),$utf8)
$err=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($pPath,[ref]$null,[ref]$err)
"parse=$($err.Count)"
if($err){ $err|Select-Object -First 8|%{$_.ToString()} }

# show ensure
$lines=Get-Content $pPath
870..900|%{ '{0}|{1}' -f $_, $lines[$_-1] }

# if still parse fail, brace-match Sync-SessionTunnelProcess function
if($err.Count -gt 0){
  $t=[IO.File]::ReadAllText($pPath)
  # count braces in file roughly
  $open=([regex]::Matches($t,'\{')).Count
  $close=([regex]::Matches($t,'\}')).Count
  "braces open=$open close=$close delta=$($open-$close)"
}
