$files = @(
  'scripts/tmp/TEST-AGENT-AUTH.md',
  'scripts/tmp/TEST-AGENT-GITMODE.md',
  'scripts/tmp/TEST-AGENT-MAC.md',
  'scripts/tmp/TEST-AGENT-PARSE.md',
  'scripts/tmp/TEST-AGENT-SERVER.md',
  'scripts/tmp/TEST-AGENT-STATIC.md',
  'scripts/tmp/TEST-GITMODE-OUT.txt',
  'scripts/tmp/TEST-PARSE-OUT.txt',
  'scripts/tmp/test-pipeline-out.txt',
  'scripts/tmp/REVIEW-LOGGING-AUTH.md'
)
# also probe critical missing
$probe = @(
  'scripts/tmp/TEST-AGENT-PIPELINE.md',
  'scripts/tmp/TEST-AGENT-PIPELINE-OUT.txt',
  'scripts/tmp/TEST-PIPELINE-OUT.txt',
  'scripts/tmp/TEST-STATIC-OUT.txt',
  'scripts/tmp/TEST-AUTH-OUT.txt',
  'scripts/tmp/TEST-SERVER-OUT.txt',
  'scripts/tmp/TEST-MAC-OUT.txt'
)
foreach ($f in $probe) {
  if (Test-Path -LiteralPath $f) { Write-Output "EXISTS: $f" } else { Write-Output "MISSING: $f" }
}
foreach ($f in $files) {
  Write-Output ""
  Write-Output "########## FILE: $f ##########"
  if (Test-Path -LiteralPath $f) {
    Get-Content -LiteralPath $f -Raw
  } else {
    Write-Output "<<FILE MISSING>>"
  }
}
