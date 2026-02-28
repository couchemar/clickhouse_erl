#!/bin/bash

# Copy pcap file from ClickHouse container to local directory
# Usage: ./scripts/copy_pcap.sh <filename> [local_filename]

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <filename> [local_filename]"
    echo ""
    echo "Available pcap files in container:"
    docker exec clickhouse ls -la /tmp/*.pcap 2>/dev/null || echo "No pcap files found"
    exit 1
fi

CONTAINER_FILE="$1"
LOCAL_FILE="${2:-$1}"
CONTAINER_NAME="clickhouse"

# Add .pcap extension if not present
if [[ "$CONTAINER_FILE" != *.pcap ]]; then
    CONTAINER_FILE="${CONTAINER_FILE}.pcap"
fi

if [[ "$LOCAL_FILE" != *.pcap ]]; then
    LOCAL_FILE="${LOCAL_FILE}.pcap"
fi

echo "Copying pcap file from container..."
echo "Container file: /tmp/$CONTAINER_FILE"
echo "Local file: $LOCAL_FILE"

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '$CONTAINER_NAME' is not running"
    exit 1
fi

# Check if file exists in container
if ! docker exec "$CONTAINER_NAME" test -f "/tmp/$CONTAINER_FILE"; then
    echo "Error: File '/tmp/$CONTAINER_FILE' not found in container"
    echo ""
    echo "Available files:"
    docker exec "$CONTAINER_NAME" sh -c "ls -1 /tmp/*.pcap 2>/dev/null | head -10" || echo "No pcap files found"
    echo ""
    echo "Use './scripts/list_pcaps.sh' to see all files with details"
    exit 1
fi

# Copy the file
docker cp "${CONTAINER_NAME}:/tmp/$CONTAINER_FILE" "$LOCAL_FILE"

# Get file info
FILE_SIZE=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null || echo "unknown")
echo ""
echo "File copied successfully!"
echo "Local file: $LOCAL_FILE"
echo "Size: $FILE_SIZE bytes"

# Show basic info about the pcap file if tcpdump is available
if command -v tcpdump >/dev/null 2>&1; then
    echo ""
    echo "Pcap file info:"
    tcpdump -r "$LOCAL_FILE" -c 5 2>/dev/null || echo "Could not read pcap file with tcpdump"
else
    echo ""
    echo "Install tcpdump locally to analyze the pcap file:"
    echo "  macOS: brew install tcpdump"
    echo "  Linux: sudo apt-get install tcpdump"
fi

echo ""
echo "You can also analyze with Wireshark or other tools"