#!/bin/bash
# RETIRED (P1.1 / 2026-08-02): this helper copied a partial file set into the live
# share and rebuilt checksums.txt from manifest.txt (narrower set than
# deploy-client-bundle.sh's find-based checksums). Interleaving the two writers
# produced self-inconsistent bundles (client checksum_fail).
#
# Do NOT use. Publish via:
#   sudo claude-server deploy-client-bundle
# (requires laptop-exec staging; server-fallback is refuse-by-default).
set -euo pipefail
echo "RETIRED: _ship-update-files.sh must not mutate /usr/local/share/claude-client." >&2
echo "Use: sudo claude-server deploy-client-bundle" >&2
echo "(find-based checksums + ship-gates + post-swap sha256sum -c)." >&2
exit 2
