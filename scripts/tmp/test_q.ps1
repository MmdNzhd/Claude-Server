$Alias='claude-server-sepidz'
function Esc([string]$t){ $t -replace "'","'\''" }
function Go([string]$label,[string]$cmd,[int]$to=20){
  Write-Host "`n## $label"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $out=& ssh -n -o BatchMode=yes -o ConnectTimeout=8 $Alias $cmd 2>&1
  $sw.Stop()
  Write-Host ("ms={0} exit={1} out={2}" -f $sw.ElapsedMilliseconds,$LASTEXITCODE,(($out -join ' ') -replace '\s+',' ').Substring(0,[Math]::Min(200,(($out -join ' ') -replace '\s+',' ').Length)))
}
Go 'plain' 'echo HI'
$e=Esc 'echo HI2'
Go 'wrapped' ("timeout 20 bash -lc '$e'")
$probe='set +e; CONF="$HOME/.claude-connect.conf"; LU=""; OS=""; PORT=""; if [ -f "$CONF" ]; then LU=$(grep -E "^LAPTOP_USER=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s\n" "$LU"'
$e2=Esc $probe
Go 'probe_wrapped' ("timeout 20 bash -lc '$e2'")
# base64
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($probe))
Go 'probe_b64' "echo $b64 | base64 -d | bash"
# single-quote style push without empty ""
$push='set +e; CLEAR=0; PREFER=; LU=Smart; PORT=21002; MODE=hide; AM=; if [ "$CLEAR" = 1 ]; then AM=; elif [ -n "$PREFER" ]; then AM=$PREFER; else AM=$(grep -E "^ACTIVE_MOUNT=" $HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s PORT=%s MODE=%s AM=%s\n" "$LU" "$PORT" "$MODE" "$AM"'
$e3=Esc $push
Go 'push_wrapped' ("timeout 20 bash -lc '$e3'")
Go 'push_b64' ("echo $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($push))) | base64 -d | bash")
