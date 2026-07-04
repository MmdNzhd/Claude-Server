$files = @(
    'd:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1',
    'd:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1',
    'd:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
)
foreach ($f in $files) {
    Write-Host "=== $f ===" -ForegroundColor Cyan
    $lineNo = 0
    foreach ($line in Get-Content $f) {
        $lineNo++
        for ($i = 0; $i -lt $line.Length; $i++) {
            $c = [int][char]$line[$i]
            if ($c -in 0x201C, 0x201D, 0x2018, 0x2019, 0x2014) {
                Write-Host ("  L{0} C{1} U+{2:X4}: {3}" -f $lineNo, $i, $c, $line.Trim())
            }
        }
    }
}
