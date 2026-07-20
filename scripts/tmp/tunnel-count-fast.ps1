$ErrorActionPreference='Stop'
function Count-File($path){
  $t = [IO.File]::ReadAllText($path)
  function C([string]$rx){ return [regex]::Matches($t,$rx).Count }
  [pscustomobject]@{
    file=(Split-Path $path -Leaf)
    bytes=(Get-Item $path).Length
    session_start=(C 'session start')
    session_end=(C 'session end')
    TUNNEL_DROP=(C 'TUNNEL_DROP')
    soft_fail=(C 'TUNNEL_SYNC soft_fail')
    TUNNEL_SYNC=(C 'TUNNEL_SYNC')
    ENSURE_TUNNEL=(C 'ENSURE_TUNNEL')
    ORPHAN=(C 'ORPHAN_TUNNEL')
    recovery=(C 'RECOVERY_BEGIN|fallthrough_recover')
    tunnel_down=(C 'tunnel_down|alreadyDown')
    user_quit=(C 'user_quit')
  }
}
Write-Output '=== FARZAD (local forensic) ==='
Count-File 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log' | Format-List | Out-String | Write-Host

# Remote counts without full download
$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','claude-server-sepidz')
$cmd = @'
echo "=== SMART remote ==="
f=/home/smart/.claude/logs/connect-20260719.log
if [ -f "$f" ]; then
  echo bytes=$(wc -c < "$f") lines=$(wc -l < "$f")
  for p in "session start" "session end" "TUNNEL_DROP" "TUNNEL_SYNC soft_fail" "TUNNEL_SYNC" "ENSURE_TUNNEL" "ORPHAN_TUNNEL" "RECOVERY_BEGIN" "fallthrough_recover" "tunnel_down" "alreadyDown" "user_quit"; do
    printf "%6s  %s\n" "$(grep -cF "$p" "$f" 2>/dev/null || echo 0)" "$p"
  done
  echo "--- DROP reasons ---"
  grep "TUNNEL_DROP" "$f" 2>/dev/null | sed "s/.*reason=/reason=/" | sort | uniq -c | sort -rn | head -20
else echo missing; fi
echo "=== other readable homes ==="
ls /home/*/.claude/logs/connect-20260719.log 2>/dev/null || echo none
'@
$out = & ssh @ssh $cmd 2>&1 | Out-String
Write-Output $out

# Farzad: classify ENSURE lines
Write-Output '=== FARZAD ENSURE line kinds ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log' -Pattern 'ENSURE_TUNNEL|ORPHAN_TUNNEL' |
  ForEach-Object { if ($_.Line -match 'ENSURE_TUNNEL[^\]]*|ORPHAN_TUNNEL[^\]]*') { $Matches[0] } else { $_.Line } } |
  ForEach-Object { ($_ -replace '\s+',' ').Substring(0,[Math]::Min(100,($_ -replace '\s+',' ').Length)) } |
  Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
  ForEach-Object { "{0,4} {1}" -f $_.Count, $_.Name }
