#!/bin/bash

# Default directory is the current working directory
TARGET_DIR="$(pwd)"
TEST_FILE="testfile"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dir) TARGET_DIR="$2"; shift ;;
        -h|--help)
            echo "Usage: $0 [--dir <directory>]"
            echo "  --dir <directory>: Specify the directory for the test (default: current working directory)"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Check if the target directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi

# Test write speed
echo "Testing write speed in directory: $TARGET_DIR"
WRITE_START=$(date +%s.%N)
dd if=/dev/zero of="$TARGET_DIR/$TEST_FILE" bs=1m count=1024 oflag=direct 2>/dev/null
WRITE_END=$(date +%s.%N)
WRITE_DURATION=$(echo "$WRITE_END - $WRITE_START" | bc)
WRITE_SPEED=$(echo "scale=2; 1024 / $WRITE_DURATION" | bc)
echo "Write Speed: $WRITE_SPEED MB/s"

# Test read speed
echo "Testing read speed in directory: $TARGET_DIR"
READ_START=$(date +%s.%N)
dd if="$TARGET_DIR/$TEST_FILE" of=/dev/null bs=1m iflag=direct 2>/dev/null
READ_END=$(date +%s.%N)
READ_DURATION=$(echo "$READ_END - $READ_START" | bc)
READ_SPEED=$(echo "scale=2; 1024 / $READ_DURATION" | bc)
echo "Read Speed: $READ_SPEED MB/s"

# Cleanup
rm -f "$TARGET_DIR/$TEST_FILE"

echo "Test completed."
