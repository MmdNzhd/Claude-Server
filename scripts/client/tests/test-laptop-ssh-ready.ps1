# test-laptop-ssh-ready.ps1 - Select-String + authorized_keys edge cases (PS 5.1)
$ErrorActionPreference = 'Stop'

function Assert($cond, $msg) {
    if (-not $cond) { throw "FAIL: $msg" }
}

# SSH key fragments often contain / and + - must not break Select-String -Pattern binding
$frag = 'AAAAC3NzaC1lZDI1NTE5AAAAINmE2C08xhilQRior6V9PApnwNh/WL2VYqa7Lk9+8Gpc'
$tmp = Join-Path $env:TEMP "claude-connect-ak-test-$([Guid]::NewGuid().ToString('N')).txt"
try {
    "from=`"127.0.0.1,::1`" ssh-ed25519 $frag claude_laptop" | Set-Content -Path $tmp -Encoding ASCII
    $pattern = [regex]::Escape($frag)
    $hit = Select-String -Path $tmp -Pattern $pattern -Quiet -ErrorAction Stop
    Assert ($hit) 'escaped pattern matches key with slash and plus'
    $miss = Select-String -Path $tmp -Pattern ([regex]::Escape('totally-other-key')) -Quiet -ErrorAction SilentlyContinue
    Assert (-not $miss) 'non-matching fragment returns false'
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

. (Join-Path $PSScriptRoot '_paths.ps1')
$src = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($src -match 'function Test-AuthorizedKeyFragment') 'connect.ps1 has Test-AuthorizedKeyFragment helper'
Assert ($src -match 'function Test-WindowsAccountIsLocalAdmin') 'connect.ps1 checks if laptop user is Windows admin'
Assert ($src -match 'administrators_authorized_keys \(Windows admin user\)') 'connect.ps1 requires admin authorized_keys for admin users'
Assert ($src -match 'administrators_authorized_keys') 'connect.ps1 checks admin authorized_keys too'
Assert ($src -notmatch 'Select-String -Path \$userAk -Pattern \[regex\]::Escape') 'no unparenthesized Select-String Pattern'

Write-Host 'OK test-laptop-ssh-ready.ps1' -ForegroundColor Green
