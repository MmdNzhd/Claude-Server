#!/bin/bash
# Run static hard + brutal + chaos adversarial suites.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 "$HERE/test-mount-heal-hard-all.py"
python3 "$HERE/test-mount-heal-brutal.py"
python3 "$HERE/test-mount-heal-chaos.py"
