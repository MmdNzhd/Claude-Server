#!/bin/bash
# Usage: bash sepidz-deploy-auth.sh 'sk-ant-oat01-...'
set -euo pipefail
TOKEN="${1:?paste token as first argument}"
PASS='sepidz@Admin'
printf '%s\n' "$PASS" | ssh sepidz@192.168.250.70 "echo '$TOKEN' | sudo -S claude-server deploy-auth '$TOKEN'"
