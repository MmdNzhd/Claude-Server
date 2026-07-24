param(
    [int[]]$ProjectSlots = @(1,2,3,5,4),
    [int]$RunsPerProject = 5,
    [int]$RoundNum = 1,
    [int]$DelayBetweenSec = 5
)
$ErrorActionPreference = 'Continue'
$cycleScript = 'D:\Smart\Claude-Code-Server\scripts\client\tests\perf\run-connect-cycle.ps1'
$resultsDir = Join-Path $env:USERPROFILE '.config\claude-connect\perf-harness'
New-Item -ItemType Directory -Force -Path $resultsDir -ErrorAction SilentlyContinue | Out-Null
$roundLog = Join-Path $resultsDir ("round-{0}.log" -f $RoundNum)
"ROUND $RoundNum START $(Get-Date -Format o)" | Out-File -FilePath $roundLog -Encoding UTF8

$all = @()
foreach ($slot in $ProjectSlots) {
    for ($i = 1; $i -le $RunsPerProject; $i++) {
        $tag = "slot=$slot run=$i/$RunsPerProject"
        "BEGIN $tag $(Get-Date -Format o)" | Out-File -FilePath $roundLog -Append -Encoding UTF8
        try {
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cycleScript -ProjectSlot $slot 2>&1
            $jsonLine = ($out | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
            if ($jsonLine) {
                $obj = $jsonLine | ConvertFrom-Json
                $all += $obj
                "END $tag totalMs=$($obj.TotalMs) steps=$($obj.Steps.Count) scorecard=$($obj.SawScorecardBoot) $(Get-Date -Format o)" | Out-File -FilePath $roundLog -Append -Encoding UTF8
            } else {
                "END $tag NO_JSON_OUTPUT $(Get-Date -Format o)" | Out-File -FilePath $roundLog -Append -Encoding UTF8
            }
        } catch {
            "ERROR $tag $($_.Exception.Message) $(Get-Date -Format o)" | Out-File -FilePath $roundLog -Append -Encoding UTF8
        }
        Start-Sleep -Seconds $DelayBetweenSec
    }
}

$summaryFile = Join-Path $resultsDir ("round-{0}-summary.json" -f $RoundNum)
$all | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryFile -Encoding UTF8
"ROUND $RoundNum DONE $(Get-Date -Format o) cycles=$($all.Count) summary=$summaryFile" | Out-File -FilePath $roundLog -Append -Encoding UTF8
