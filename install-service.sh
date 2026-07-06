#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="$SCRIPT_DIR/helix-ui.service"

if [ ! -f "$SERVICE_FILE" ]; then
  echo "Error: helix-ui.service not found in $SCRIPT_DIR"
  exit 1
fi

echo "Installing H E L I X UI service..."
echo "Make sure you've edited helix-ui.service with your username and paths first!"
echo ""

sudo cp "$SERVICE_FILE" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable helix-ui
sudo systemctl start helix-ui
sudo systemctl status helix-ui
