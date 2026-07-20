$path = (Resolve-Path (Join-Path $PSScriptRoot '..\server\commands\install-client-bundle.sh')).Path
$c = Get-Content $path -Raw
$old = @'
command -v unzip >/dev/null 2>&1 || fail "unzip not installed (apt install unzip)"

BUNDLE_ROOT="/usr/local/share/claude-client"
STAGE="/var/tmp/claude-client-bundle-staging.$$"

cleanup() {
    if [ -d "$STAGE" ]; then
        rm -rf "$STAGE"
    fi
}
trap cleanup EXIT

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's/\r$//' "$f"
}

echo ""
echo -e "${BOLD}Install client bundle from ZIP${NC}"
echo -e "  ${BOLD}source${NC}  $ZIP"
echo -e "  ${BOLD}target${NC}  $BUNDLE_ROOT"
echo ""

rm -rf "$STAGE"
mkdir -p "$STAGE"
unzip -q -o "$ZIP" -d "$STAGE"
'@

$new = @'
BUNDLE_ROOT="/usr/local/share/claude-client"
STAGE="/var/tmp/claude-client-bundle-staging.$$"

cleanup() {
    if [ -d "$STAGE" ]; then
        rm -rf "$STAGE"
    fi
}
trap cleanup EXIT

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's/\r$//' "$f"
}

_extract_zip() {
    local zip="$1" dest="$2"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$zip" -d "$dest"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$zip" "$dest" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
        return 0
    fi
    fail "need unzip or python3 to extract bundle.zip"
}

echo ""
echo -e "${BOLD}Install client bundle from ZIP${NC}"
echo -e "  ${BOLD}source${NC}  $ZIP"
echo -e "  ${BOLD}target${NC}  $BUNDLE_ROOT"
echo ""

rm -rf "$STAGE"
mkdir -p "$STAGE"
_extract_zip "$ZIP" "$STAGE"
'@

if ($c -notmatch '_extract_zip') {
    $c = $c.Replace($old, $new)
    Set-Content $path -Value $c -Encoding UTF8 -NoNewline
    Write-Host 'patched install-client-bundle.sh'
} else {
    Write-Host 'already patched'
}
