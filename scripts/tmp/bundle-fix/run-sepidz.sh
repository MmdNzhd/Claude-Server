#!/bin/bash
set -eu
echo 'sepidz@Admin' | sudo -S bash -c '
set -e
DEST=/usr/local/share/claude-client
cp /tmp/editor-launch.ps1 $DEST/editor-launch.ps1
cp /tmp/connect.ps1 $DEST/connect.ps1
cp /tmp/connect-version.txt $DEST/connect-version.txt
chmod 644 $DEST/editor-launch.ps1 $DEST/connect.ps1 $DEST/connect-version.txt
# nested windows/ if exists
if [ -d $DEST/windows ]; then
  cp /tmp/editor-launch.ps1 $DEST/windows/editor-launch.ps1
  cp /tmp/connect.ps1 $DEST/windows/connect.ps1
  cp /tmp/connect-version.txt $DEST/windows/connect-version.txt
fi
grep -q preserve_open_windows $DEST/editor-launch.ps1
grep -q 20260715.18 $DEST/connect-version.txt
! grep -q pre_launch_agent_or_new_window $DEST/editor-launch.ps1 || { echo STILL_HAS_FORCE; exit 1; }
echo SEPIDZ_BUNDLE_OK
'
