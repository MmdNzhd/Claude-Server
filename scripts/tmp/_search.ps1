Write-Output '=== sshx definitions ==='
Select-String -Path scripts/client/**/*.sh,scripts/client/*.sh -Pattern 'sshx\(\)|bash -lc|base64 -d' -ErrorAction SilentlyContinue |
  ForEach-Object { "$($_.Path.Replace((Get-Location).Path+'\','')):$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(110,$_.Line.Trim().Length)))" }

Write-Output '=== dangerous single-quote patterns in sshx strings ==='
# lines with sshx "....'....'
Get-ChildItem scripts/client -Recurse -Include *.sh | ForEach-Object {
  $i=0
  Get-Content $_.FullName | ForEach-Object {
    $i++
    if ($_ -match 'sshx\s+"' -and $_ -match "'") {
      $rel = $_.FullName
    }
  }
}
Get-ChildItem scripts/client -Recurse -Filter *.sh | ForEach-Object {
  $path = $_.FullName
  $rel = $path.Substring((Resolve-Path scripts/client).Path.Length+1)
  $n=0
  foreach ($line in [IO.File]::ReadAllLines($path)) {
    $n++
    if ($line -match 'sshx' -and $line -match "'") {
      Write-Output ("{0}:{1}:{2}" -f $rel,$n,$line.Trim().Substring(0,[Math]::Min(130,$line.Trim().Length)))
    }
  }
}

Write-Output '=== grep -E with caret in single quotes (repo) ==='
Get-ChildItem scripts/client -Recurse -Filter *.sh | ForEach-Object {
  $rel = $_.FullName.Substring((Resolve-Path scripts/client).Path.Length+1)
  Select-String -Path $_.FullName -Pattern "grep -E '\^" | ForEach-Object {
    Write-Output ("{0}:{1}:{2}" -f $rel,$_.LineNumber,$_.Line.Trim())
  }
}

Write-Output '=== ssh-keygen -N empty single quotes ==='
Get-ChildItem scripts/client -Recurse -Include *.sh,*.ps1 | ForEach-Object {
  Select-String -Path $_.FullName -Pattern "ssh-keygen.*-N ''" | ForEach-Object {
    $rel = $_.Path.Substring((Resolve-Path scripts/client).Path.Length+1)
    Write-Output ("{0}:{1}:{2}" -f $rel,$_.LineNumber,$_.Line.Trim())
  }
}

Write-Output '=== designer connect sshx ==='
if (Test-Path scripts/client/users/designer/connect.sh) {
  Select-String -Path scripts/client/users/designer/connect.sh -Pattern 'sshx\(\)|bash -lc|base64' |
    ForEach-Object { "designer:$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)))" }
}
