# Simulate ض on Q
$code = [int][char]'ض'
$ascii = ($code -ge 32 -and $code -le 126)
$letter = if ($ascii) { 'ض'.ToLowerInvariant() } else { '' }
$useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
Write-Output "DAD code=$code ascii=$ascii letter='$letter' useVk=$useVk expect_quit=$false resolved_would_be_q=$(($letter -eq 'q') -or ($useVk))"

# Simulate English q
$code = [int][char]'q'
$ascii = ($code -ge 32 -and $code -le 126)
$letter = if ($ascii) { 'q'.ToLowerInvariant() } else { '' }
$useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
Write-Output "q code=$code ascii=$ascii letter='$letter' useVk=$useVk expect_quit=$true"

# Simulate Enter (KeyChar often \r = 13)
$code = 13
$ascii = ($code -ge 32 -and $code -le 126)
$letter = if ($ascii) { '' } else { '' }
$useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
Write-Output "Enter code=$code ascii=$ascii useVk=$useVk (Enter key still maps via ConsoleKey::Enter separately)"

Select-String -Path D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1 -Pattern 'useVk|fallthrough_recover|ignore_empty_action' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Get-Content D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt
