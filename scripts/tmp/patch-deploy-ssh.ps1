$path='D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
$c=[IO.File]::ReadAllText($path)
$old="-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no'"
# Multiple patterns for ssh/scp
$replacements=@(
  @{o="-o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no";
    n="-o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -o IdentitiesOnly=yes -o IdentityAgent=none"},
  @{o="-o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no";
    n="-o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -o IdentitiesOnly=yes -o IdentityAgent=none"},
  @{o="'-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no'";
    n="'-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none'"}
)
foreach($r in $replacements){
  $count=([regex]::Matches($c,[regex]::Escape($r.o))).Count
  Write-Output ("replace count=$count for: $($r.o.Substring(0,[Math]::Min(50,$r.o.Length)))")
  $c=$c.Replace($r.o,$r.n)
}
[IO.File]::WriteAllText($path,$c)
Write-Output 'patched deploy-client-bundles.ps1'
