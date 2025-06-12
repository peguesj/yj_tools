#!/bin/zsh
# -----------------------------------------------------------------------------
# btau - Wrapper for BTAU.sh
#
# Version: v1.3.0 (2025-02-28)
#
# Authors:
#   - Jeremiah Pegues <jeremiah@pegues.io> - https://pegues.io
#   - OPSGAÃNG Sistemi <word@iite.bet> - https://iite.bet/ardela/schemas
#
# Description:
#   This wrapper script calls the BTAU.sh backup script with default parameters:
#
#       --no-env --zip-by sub 1 --comp maximum --format targz --log-level INFO --name dir
#
#   It uses the variable BTAU_DIR to locate BTAU.sh. The placeholder __BTAU_DIR__
#   should be replaced with the actual directory path during installation.
#
# -----------------------------------------------------------------------------

BTAU_DIR="__BTAU_DIR__"
BTAU_SCRIPT="$BTAU_DIR/BTAU.sh"

if [ ! -f "$BTAU_SCRIPT" ]; then
    echo "[ERROR] BTAU.sh not found in $BTAU_DIR. Please verify your installation."
    exit 1
fi

exec "$BTAU_SCRIPT" --no-env --zip-by sub 1 --comp maximum --format targz --log-level INFO --name dir "$@"