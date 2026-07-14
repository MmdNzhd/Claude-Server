#!/bin/bash
# test-windows-connect.sh - static checks for Windows connect parity with Mac
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WIN="$ROOT/scripts/client/windows/connect.ps1"
GIT="$ROOT/scripts/client/git-mode.ps1"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$WIN" ] || fail "windows/connect.ps1 missing"
[ -f "$GIT" ] || fail "git-mode.ps1 missing"

grep -q 'Ensure-SessionTunnel' "$GIT" || fail 'missing Ensure-SessionTunnel'
grep -q 'Acquire-TunnelPort' "$GIT" || fail 'missing Acquire-TunnelPort'
grep -q 'Sanitize-SshAliasConfig' "$GIT" || fail 'missing Sanitize-SshAliasConfig'
grep -q 'Release-StaleTunnelPort' "$GIT" || fail 'missing Release-StaleTunnelPort'
grep -q 'Ensure-LaptopReverseSshCached' "$GIT" || fail 'missing Ensure-LaptopReverseSshCached'
grep -q 'Ensure-LaptopReverseSsh' "$GIT" || fail 'missing Ensure-LaptopReverseSsh'
grep -q 'timeout 30.*recover' "$GIT" || fail 'Invoke-RecoverIfNeeded must use timeout + recover fallback'
grep -A25 'function Remount-ProjectGit' "$GIT" | grep -q 'CLAUDE_TRUSTED_TUNNEL=1' || fail 'Remount-ProjectGit must use trusted tunnel'
grep -q 'Prepare-ServerSessionParallel' "$GIT" || fail 'missing Prepare-ServerSessionParallel'
grep -q 'Invoke-RecoverIfNeeded' "$GIT" || fail 'missing Invoke-RecoverIfNeeded'
grep -q 'TrustedTunnel' "$GIT" || fail 'missing TrustedTunnel mount path'
grep -q 'ExitOnForwardFailure=yes' "$GIT" || fail 'tunnel must use ExitOnForwardFailure=yes'

grep -q 'if (-not \$c) { continue }' "$WIN" || fail 'empty Enter must not select default project'
grep -q 'Get-MountsForLaptop' "$WIN" || fail 'missing OS project filter'
grep -q 'Ensure-LaptopReverseSshCached' "$WIN" || fail 'connect.ps1 must verify before mount'
grep -q 'Ensure-SessionTunnel' "$WIN" || fail 'connect.ps1 must use Ensure-SessionTunnel'
grep -q 'TrustedTunnel' "$WIN" || fail 'connect.ps1 must use trusted mount'
grep -q 'Prepare-ServerSessionParallel' "$WIN" || fail 'connect.ps1 must use parallel session prep'
grep -q 'Invoke-RecoverIfNeeded' "$WIN" || fail 'connect.ps1 must use conditional recover'
! grep -q 'RemoteForward \$Port' "$WIN" || fail 'RemoteForward must not be in connect.ps1 ssh config'
grep -q 'Sanitize-SshAliasConfig' "$WIN" || fail 'connect.ps1 must sanitize ssh config'
grep -q 'Acquire-TunnelPort' "$WIN" || fail 'connect.ps1 must acquire tunnel slot'
grep -q "already exists" "$WIN" || fail 'connect.ps1 must reject duplicate project ids'

echo 'OK test-windows-connect.sh'
