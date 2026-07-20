$adminAk = 'C:\ProgramData\ssh\administrators_authorized_keys'
$frag = 'AAAAC3NzaC1lZDI1NTE5AAAAINmE2C08xhilQRior6V9PApnwNh/WL2VYqa7Lk9+8Gpc'
Write-Host "elevated=$([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
$wi = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($wi)
Write-Host "IsAdminToken=$($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
Write-Host "User=$($wi.Name)"
try {
  $c = Get-Content -LiteralPath $adminAk -ErrorAction Stop
  Write-Host "Get-Content OK lines=$($c.Count)"
} catch {
  Write-Host "Get-Content FAIL $($_.Exception.Message)"
}
try {
  $hit = [bool](Select-String -Path $adminAk -Pattern ([regex]::Escape($frag)) -Quiet -ErrorAction Stop)
  Write-Host "Select-String hit=$hit"
} catch {
  Write-Host "Select-String FAIL $($_.Exception.Message)"
}
# replicate Test-AuthorizedKeyFragment
$r = $false
if ($frag -and (Test-Path $adminAk)) {
  $r = [bool](Select-String -Path $adminAk -Pattern ([regex]::Escape($frag)) -Quiet -ErrorAction SilentlyContinue)
}
Write-Host "Test-AuthorizedKeyFragment replica=$r"
