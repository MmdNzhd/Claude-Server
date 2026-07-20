from pathlib import Path

# Hardcode Sepidz sudo into Get-DeployCredentials (user-requested).
cred = Path(r"D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1")
t = cred.read_text(encoding="utf-8")
old = '''function Get-SepidzSudoPassword {
    if ($env:SEPIDZ_SUDO_PASSWORD) { return $env:SEPIDZ_SUDO_PASSWORD.Trim() }
    return Read-SepidzLocalValue -Name 'SepidzSudoPassword'
}'''
new = '''function Get-SepidzSudoPassword {
    if ($env:SEPIDZ_SUDO_PASSWORD) { return $env:SEPIDZ_SUDO_PASSWORD.Trim() }
    $v = Read-SepidzLocalValue -Name 'SepidzSudoPassword'
    if ($v) { return $v }
    # Hardcoded Sepidz sudo (ops requested). Prefer env / sepidz-deploy.local.ps1 when present.
    return 'sepidz@Admin'
}'''
if old not in t:
    if "return 'sepidz@Admin'" in t:
        print("SKIP cred already hardcoded")
    else:
        raise SystemExit("cred pattern missing")
else:
    cred.write_text(t.replace(old, new), encoding="utf-8", newline="\n")
    print("OK hardcoded in Get-DeployCredentials.ps1")

# Also force Sepidz path in deploy-client-bundles to always use password string fallback
dep = Path(r"D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1")
d = dep.read_text(encoding="utf-8")
old2 = '''        $sudoPw = ''
        if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword }
        if ($target.Label -eq 'Smart') { $sudoPw = Get-SmartSudoPassword }'''
# tolerate whitespace variants
import re
m = re.search(r"\$sudoPw\s*=\s*''\s*\r?\n\s*if \(\$target\.Label -eq 'Sepidz'\) \{ \$sudoPw = Get-SepidzSudoPassword \}\s*\r?\n\s*if \(\$target\.Label -eq 'Smart'\) \{ \$sudoPw = Get-SmartSudoPassword \}", d)
new2 = '''        $sudoPw = ''
        if ($target.Label -eq 'Sepidz') {
            $sudoPw = Get-SepidzSudoPassword
            if (-not $sudoPw) { $sudoPw = 'sepidz@Admin' }
        }
        if ($target.Label -eq 'Smart') { $sudoPw = Get-SmartSudoPassword }'''
if m:
    d = d[:m.start()] + new2 + d[m.end():]
    dep.write_text(d, encoding="utf-8", newline="\n")
    print("OK hardcoded fallback in deploy-client-bundles.ps1")
elif "sepidz@Admin" in d and "Get-SepidzSudoPassword" in d:
    print("SKIP deploy maybe already has fallback")
else:
    # try simpler replace
    if "if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword }" in d:
        d = d.replace(
            "if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword }",
            "if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword; if (-not $sudoPw) { $sudoPw = 'sepidz@Admin' } }",
        )
        dep.write_text(d, encoding="utf-8", newline="\n")
        print("OK simple fallback in deploy-client-bundles.ps1")
    else:
        raise SystemExit("deploy pattern missing")

# Ensure local file also has it
local = Path(r"D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1")
local.write_text(
    "# Local only — gitignored. Do not commit.\n"
    "$SepidzSshUser = 'sepidz'\n"
    "$SepidzSudoPassword = 'sepidz@Admin'\n",
    encoding="utf-8",
    newline="\n",
)
print("OK refreshed sepidz-deploy.local.ps1")
