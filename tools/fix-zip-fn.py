from pathlib import Path
import re
p = Path('publish/publish.ps1')
t = p.read_text(encoding='utf-8')
old = '''function New-ClientZipFromDirectory {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$ZipPath
    )
    Add-Type -AssemblyName System.IO.Compression



Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }'''
new = '''function New-ClientZipFromDirectory {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$ZipPath
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }'''
if old in t:
    t = t.replace(old, new, 1)
    p.write_text(t, encoding='utf-8', newline='\n')
    print('cleaned New-ClientZipFromDirectory')
else:
    print('pattern not exact; checking function body start')
    i = t.find('function New-ClientZipFromDirectory')
    print(repr(t[i:i+350]))

# Ensure Clear function has matching braces - quick count
i = t.find('function Clear-PublishedWindowsToExeOnly')
j = t.find('function New-ClientZipFromDirectory')
chunk = t[i:j]
print('Clear chunk braces', chunk.count('{'), chunk.count('}'))
print('call present', 'Clear-PublishedWindowsToExeOnly -ClientRoot $OutDir' in t)
