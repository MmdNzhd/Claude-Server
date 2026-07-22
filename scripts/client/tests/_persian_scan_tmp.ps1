$files = Get-ChildItem -Path 'scripts\client' -Recurse -Include *.sh,*.ps1,*.bat
$pattern = '[\u0600-\u06FF\u200C\u200F\uFB50-\uFDFF\uFE70-\uFEFF]'
$found = $false
foreach ($f in $files) {
    $content = Get-Content -Raw -Encoding UTF8 $f.FullName -ErrorAction SilentlyContinue
    if ($content -and ($content -match $pattern)) {
        $found = $true
        $lines = $content -split "`n"
        for ($i=0; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -match $pattern) {
                Write-Output "$($f.FullName):$($i+1): $($lines[$i])"
            }
        }
    }
}
if (-not $found) { Write-Output "NO_PERSIAN_FOUND" }
