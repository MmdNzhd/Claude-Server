# Per CLAUDE.md: Sepidz via Host claude-server-sepidz; IdentityAgent=none when agent refuses.
$ErrorActionPreference='Continue'
function Run-Ssh([string]$Target,[string]$Cmd){
  $args=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',$Target,$Cmd)
  $out=Join-Path $env:TEMP 'live-ssh-out.txt'
  $err=Join-Path $env:TEMP 'live-ssh-err.txt'
  $p=Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  [pscustomobject]@{
    Target=$Target; Exit=$p.ExitCode
    Out=((Get-Content $out -Raw -EA SilentlyContinue) -replace '\s+$','')
    Err=((Get-Content $err -Raw -EA SilentlyContinue) -replace '\s+$','')
  }
}
Write-Output '=== ssh config hosts ==='
if(Test-Path "$env:USERPROFILE\.ssh\config"){
  Select-String -Path "$env:USERPROFILE\.ssh\config" -Pattern 'Host |HostName |User ' | Select-Object -First 40 | ForEach-Object { $_.Line.Trim() }
}
Write-Output '=== Sepidz Host alias ==='
$r1=Run-Ssh 'claude-server-sepidz' "hostname; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo"
"exit=$($r1.Exit) out=$($r1.Out) err=$($r1.Err)"
Write-Output '=== Sepidz IP ==='
$r2=Run-Ssh 'sepidz@192.168.250.70' "hostname; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo"
"exit=$($r2.Exit) out=$($r2.Out) err=$($r2.Err)"
Write-Output '=== Smart Host alias candidates ==='
foreach($h in @('claude-server','smart-internet','smart@192.168.210.240')){
  $r=Run-Ssh $h "hostname; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo"
  "host=$h exit=$($r.Exit) out=$($r.Out) err=$($r.Err)"
}
