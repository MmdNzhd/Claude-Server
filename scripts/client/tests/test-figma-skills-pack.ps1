#Requires -Version 5.1
# Figma skills pack: required trees, router, deploy wiring (repo-side).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"
$fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "PASS  $Msg" }
    else { Write-Host "FAIL  $Msg"; $script:fail++ }
}

$required = @(
    'server\skills\figma-use\SKILL.md',
    'server\skills\figma-use\references\gotchas.md',
    'server\skills\figma-use\references\plugin-api-standalone.d.ts',
    'server\skills\figma-generate-design\SKILL.md',
    'server\skills\figma-create-new-file\SKILL.md',
    'server\skills\figma-designer\SKILL.md',
    'server\skills\FIGMA-SKILLS-VENDOR.md'
)
foreach ($rel in $required) {
    $p = Get-ServerFile $rel
    Assert (Test-Path -LiteralPath $p) "exists $rel"
}

$dts = Get-ServerFile 'server\skills\figma-use\references\plugin-api-standalone.d.ts'
if (Test-Path -LiteralPath $dts) {
    Assert ((Get-Item -LiteralPath $dts).Length -gt 100000) 'plugin-api-standalone.d.ts > 100KB'
}

$router = Get-ServerFile 'server\skills\figma-designer\SKILL.md'
if (Test-Path -LiteralPath $router) {
    $r = Get-Content -LiteralPath $router -Raw
    Assert ($r -match '(?m)^name:\s*figma-designer\s*$') 'figma-designer frontmatter name'
    Assert ($r -match 'figma-use') 'figma-designer requires figma-use'
    Assert ($r -match 'figma-generate-design') 'figma-designer mentions figma-generate-design'
    Assert ($r -match 'Using this Figma file:') 'figma-designer has pasteable prompt template'
    Assert ($r -match 'Intent router|skill-map|hard-gates') 'figma-designer is orchestrator (not thin stub)'
}
foreach ($ref in @(
    'server\skills\figma-designer\references\skill-map.md',
    'server\skills\figma-designer\references\canvas-workflows.md',
    'server\skills\figma-designer\references\hard-gates.md',
    'server\skills\figma-designer\references\club-design-kit.md'
)) {
    Assert (Test-Path -LiteralPath (Get-ServerFile $ref)) "exists $ref"
}

$clubKit = Get-ServerFile 'server\skills\figma-designer\references\club-design-kit.md'
if (Test-Path -LiteralPath $clubKit) {
    $ck = Get-Content -LiteralPath $clubKit -Raw
    Assert ($ck -match 'YR4B9skUnJe50tnfCyRwYo') 'club-design-kit has Club fileKey'
    Assert ($ck -match 'IRANYekanXFaNum') 'club-design-kit documents Club font'
    Assert ($ck -match 'Design Kit V\.2') 'club-design-kit documents Design Kit V.2'
    Assert ($ck -match 'libraryKey') 'club-design-kit has libraryKey'
}

if (Test-Path -LiteralPath $router) {
    $r2 = Get-Content -LiteralPath $router -Raw
    Assert ($r2 -match 'club-design-kit') 'figma-designer references club-design-kit'
}

$rule = Get-ServerFile 'server\cursor-rules\figma-design.mdc'
$ruleRaw = Get-Content -LiteralPath $rule -Raw
Assert ($ruleRaw -match 'figma-designer') 'figma-design.mdc points to figma-designer'
Assert ($ruleRaw -match 'write to canvas|in-Figma|inside Figma|use_figma') 'figma-design.mdc covers write-to-canvas'

$docs = Join-Path $script:RepoRoot 'docs\cursor-mcp-pack.md'
$docsRaw = Get-Content -LiteralPath $docs -Raw
Assert ($docsRaw -match 'Designer quick prompts|figma-designer') 'cursor-mcp-pack.md designer prompts'

$install = Get-Content (Get-ServerFile 'server\commands\install.sh') -Raw
Assert ($install -match 'figma-use') 'install.sh deploys figma-use'
Assert ($install -match 'figma-generate-design') 'install.sh deploys figma-generate-design'
Assert ($install -match 'figma-create-new-file') 'install.sh deploys figma-create-new-file'
Assert ($install -match 'figma-designer') 'install.sh deploys figma-designer'

$addUser = Get-Content (Get-ServerFile 'server\commands\add-user.sh') -Raw
Assert ($addUser -match 'figma-use') 'add-user.sh deploys figma-use'
Assert ($addUser -match 'figma-designer') 'add-user.sh deploys figma-designer'

$verify = Get-Content (Get-ServerFile 'server\commands\verify.sh') -Raw
Assert ($verify -match 'figma-use/SKILL\.md') 'verify.sh checks figma-use skill'
Assert ($verify -match 'club-design-kit') 'verify.sh checks club-design-kit'

if ($fail -gt 0) { Write-Host "`n$fail FAIL(s)"; exit 1 }
Write-Host "`nALL PASS"
exit 0
