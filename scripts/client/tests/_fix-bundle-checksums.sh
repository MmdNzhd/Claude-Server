#!/bin/bash
# RETIRED (P1.1 / 2026-08-02): rebuilt checksums.txt from manifest.txt (narrower
# file set) while deploy-client-bundle.sh uses find (broader). That mismatch
# caused self-inconsistent bundles when both paths touched the same share.
#
# Do NOT use. Checksums are owned exclusively by:
#   sudo claude-server deploy-client-bundle
set -euo pipefail
echo "RETIRED: _fix-bundle-checksums.sh must not rewrite checksums.txt." >&2
echo "Use: sudo claude-server deploy-client-bundle" >&2
echo "(find-based checksums + post-swap sha256sum -c)." >&2
exit 2
