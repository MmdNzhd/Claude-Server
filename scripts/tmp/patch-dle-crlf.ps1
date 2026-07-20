$ErrorActionPreference = 'Stop'
$p = 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh'
$raw = [IO.File]::ReadAllText($p)
if ($raw -match 'sed -i .s/\\r\$//. /usr/local/bin/laptop-exec') {
  Write-Host 'already patched'
  exit 0
}
$old = "install -m 755 `"`$SERVER_DIR/laptop-exec.sh`" /usr/local/bin/laptop-exec`nok `"laptop-exec -> /usr/local/bin/`""
# try unix newlines
$old2 = "install -m 755 `"$SERVER_DIR/laptop-exec.sh`" /usr/local/bin/laptop-exec`nok `"laptop-exec -> /usr/local/bin/`""
# Read actual snippet
$idx = $raw.IndexOf('install -m 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec')
if ($idx -lt 0) { throw 'install line not found' }
$snip = $raw.Substring($idx, [Math]::Min(180, $raw.Length-$idx))
Write-Host "SNIP=<<$snip>>"
$oldExact = "install -m 755 `"`$SERVER_DIR/laptop-exec.sh`" /usr/local/bin/laptop-exec`nok `"laptop-exec -> /usr/local/bin/`""
# In file the $ is literal $SERVER_DIR
$oldExact = @'
install -m 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec
ok "laptop-exec -> /usr/local/bin/"
'@
$newExact = @'
install -m 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec
# Windows zip/scp can leave CRLF and break bash ($'\r': command not found).
sed -i 's/\r$//' /usr/local/bin/laptop-exec "$SERVER_DIR/laptop-exec.sh" 2>/dev/null || true
ok "laptop-exec -> /usr/local/bin/"
'@
if (-not $raw.Contains($oldExact)) { throw 'exact anchor missing' }
$raw2 = $raw.Replace($oldExact, $newExact)

# also strip after copying to each user home
$oldUser = @'
  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"
'@
$newUser = @'
  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"
  sed -i 's/\r$//' "$h/.local/bin/laptop-exec" 2>/dev/null || true
'@
if ($raw2.Contains($oldUser) -and -not $raw2.Contains("sed -i 's/\r$//' `"$h/.local/bin/laptop-exec`"")) {
  $raw2 = $raw2.Replace($oldUser, $newUser)
}
[IO.File]::WriteAllText($p, $raw2)
Write-Host 'PATCHED_OK'
