#!/bin/bash
# Run as ROOT on server to configure shared ANTHROPIC_API_KEY for all users
# Usage: sudo bash setup-claude-auth.sh <your-api-key>
# Get your API key from: https://console.anthropic.com/

set -e

API_KEY="${1:-}"

if [ -z "$API_KEY" ]; then
    echo "Usage: sudo bash setup-claude-auth.sh sk-ant-api03-..."
    echo ""
    echo "Get your API key from: https://console.anthropic.com/"
    exit 1
fi

if [[ ! "$API_KEY" == sk-ant-* ]]; then
    echo "ERROR: API key should start with 'sk-ant-'"
    exit 1
fi

echo "=== Setting up shared ANTHROPIC_API_KEY ==="

cat > /etc/profile.d/claude-key.sh << EOF
export ANTHROPIC_API_KEY="$API_KEY"
EOF
chmod 644 /etc/profile.d/claude-key.sh

echo "  OK: /etc/profile.d/claude-key.sh created"
echo ""
echo "=== Verify Claude is in PATH ==="

CLAUDE_PATH=$(find /usr -name claude -type f 2>/dev/null | head -1)
if [ -z "$CLAUDE_PATH" ]; then
    CLAUDE_PATH=$(find /root -name claude -type f 2>/dev/null | head -1)
fi

if [ -n "$CLAUDE_PATH" ]; then
    ln -sf "$CLAUDE_PATH" /usr/local/bin/claude 2>/dev/null || true
    chmod 755 /usr/local/bin/claude
    echo "  OK: claude linked at /usr/local/bin/claude -> $CLAUDE_PATH"
else
    echo "  WARNING: claude binary not found. Install with:"
    echo "    sudo npm install -g @anthropic-ai/claude-code"
fi

echo ""
echo "Done. All users now have ANTHROPIC_API_KEY set automatically."
echo "Each new user still needs to run 'claude' once to accept terms."
