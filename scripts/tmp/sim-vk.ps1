function Resolve([char]$ch, [ConsoleKey]$key) {
  $code = [int]$ch
  $ascii = ($code -ge 32 -and $code -le 126)
  $letter = if ($ascii) { ([string]$ch).ToLowerInvariant() } else { '' }
  $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
  $resolved = ''
  if ($letter -eq 'r' -or ($useVk -and $key -eq [ConsoleKey]::R)) { $resolved = 'r' }
  elseif ($letter -eq 'g' -or ($useVk -and $key -eq [ConsoleKey]::G)) { $resolved = 'g' }
  elseif ($letter -eq 'o' -or ($useVk -and $key -eq [ConsoleKey]::O)) { $resolved = 'o' }
  elseif ($letter -eq 'q' -or ($useVk -and $key -eq [ConsoleKey]::Q) -or $key -eq [ConsoleKey]::Enter) { $resolved = 'q' }
  [pscustomobject]@{ch=[string]$ch; code=('U+{0:X4}' -f $code); ascii=$ascii; letter=$letter; useVk=$useVk; key=$key; resolved=$resolved; ignore=[string]::IsNullOrEmpty($resolved)}
}
# ض via unicode escape
$dad = [char]0x0636
Resolve $dad ([ConsoleKey]::Q) | Format-List
Resolve 'q' ([ConsoleKey]::Q) | Format-List
Resolve ([char]13) ([ConsoleKey]::Enter) | Format-List
Resolve 'x' ([ConsoleKey]::X) | Format-List
