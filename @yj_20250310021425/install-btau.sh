#!/bin/zsh
# -----------------------------------------------------------------------------
# install-btau.sh - Installs the btau wrapper into /usr/local/bin
#
# Version: v1.3.0 (2025-02-28)
#
# Authors:
#   - Jeremiah Pegues <jeremiah@pegues.io> - https://pegues.io
#   - OPSGAÃNG Sistemi <word@iite.bet> - https://iite.bet/ardela/schemas
#
# Description:
#   This script uses the current working directory (PWD) as the directory holding
#   the BTAU.sh and btau-wrapper.sh scripts. It substitutes the __BTAU_DIR__ placeholder
#   in the wrapper with the actual PWD and installs the resulting script to 
#   /usr/local/bin/btau.
#
# Usage:
#   ./install-btau.sh
#
# -----------------------------------------------------------------------------

# Get the current directory (assumed to contain BTAU.sh and btau-wrapper.sh)
BTAU_DIR="$(pwd)"
echo "Installing BTAU wrapper from directory: $BTAU_DIR"

# Path to the wrapper template (ensure this file is in the current directory)
WRAPPER_TEMPLATE="./btau-wrapper.sh"
if [ ! -f "$WRAPPER_TEMPLATE" ]; then
    echo "[ERROR] btau-wrapper.sh not found in $BTAU_DIR"
    exit 1
fi

# Destination path for the wrapper script
INSTALL_PATH="/usr/local/bin/btau"

# Substitute the placeholder __BTAU_DIR__ with the actual BTAU_DIR value
sed "s|__BTAU_DIR__|$BTAU_DIR|g" "$WRAPPER_TEMPLATE" > /tmp/btau_temp_wrapper.sh

# Copy the modified wrapper to /usr/local/bin and set it executable
sudo cp /tmp/btau_temp_wrapper.sh "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"
rm /tmp/btau_temp_wrapper.sh

echo "BTAU wrapper installed to $INSTALL_PATH"