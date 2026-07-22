from pathlib import Path
p = Path('publish/publish.ps1')
t = p.read_text(encoding='utf-8')

# Extract the broken nested function and remove it from inside New-ClientZipFromDirectory
start = t.find('function Clear-PublishedWindowsToExeOnly {')
if start < 0:
    raise SystemExit('function missing')
# find matching end: next "\nfunction " or the Add-Type that should follow at wrong place
# The insert left: Add-Type Compression \n \n function Clear... \n ... \n}\n\n then original body of New-ClientZip?

# Show structure around start
print('BEFORE FIX CONTEXT:')
print(repr(t[start-80:start+100]))

# Find end of Clear-Published function: look for Write-Ok line then closing brace
marker_end = "Write-Ok 'windows\\ reduced to Claude-Connect.exe only (ZIP/deploy already used full tree)'\n}"
idx_end = t.find(marker_end, start)
if idx_end < 0:
    marker_end = 'Write-Ok \'windows\\ reduced to Claude-Connect.exe only (ZIP/deploy already used full tree)\'\n}'
    idx_end = t.find("Write-Ok 'windows\\ reduced to Claude-Connect.exe only", start)
    if idx_end < 0:
        raise SystemExit('end marker missing')
    # find closing } after Write-Ok
    brace = t.find('\n}', idx_end)
    end = brace + 2
else:
    end = idx_end + len(marker_end)

func = t[start:end].strip() + '\n\n'
# Remove from current location - also remove accidental blank lines after Add-Type Compression
# What was before: Add-Type -AssemblyName System.IO.Compression\n    \nfunction Clear...
# Should become: Add-Type -AssemblyName System.IO.Compression\n

before = t[:start]
after = t[end:]
# Clean double newlines / orphan
if before.rstrip().endswith('Add-Type -AssemblyName System.IO.Compression'):
    before = before.rstrip() + '\n'
t2 = before + after

# Insert function just BEFORE New-ClientZipFromDirectory at script scope
anchor = 'function New-ClientZipFromDirectory {'
if anchor not in t2:
    raise SystemExit('New-ClientZipFromDirectory missing')
if 'function Clear-PublishedWindowsToExeOnly {' in t2:
    raise SystemExit('still has nested or leftover function')
t2 = t2.replace(anchor, func + anchor, 1)
p.write_text(t2, encoding='utf-8', newline='\n')
print('moved function to script scope')
# verify
t3 = p.read_text(encoding='utf-8')
i = t3.find('function Clear-PublishedWindowsToExeOnly')
j = t3.find('function New-ClientZipFromDirectory')
print('Clear at', i, 'New-ClientZip at', j, 'order_ok', i < j)
# ensure not nested: count braces between Clear and New-ClientZip - Clear should close before New
print(t3[i:i+120])
