#!/bin/bash

# List all pcap files in the ClickHouse container
# Usage: ./scripts/list_pcaps.sh

set -e

CONTAINER_NAME="clickhouse"

echo "Listing pcap files in container '$CONTAINER_NAME'..."

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '$CONTAINER_NAME' is not running"
    echo "Start it with: docker-compose up -d"
    exit 1
fi

# List pcap files with details
echo ""
docker exec "$CONTAINER_NAME" sh -c "
    if ls /tmp/*.pcap >/dev/null 2>&1; then
        echo 'Available pcap files:'
        ls -lah /tmp/*.pcap
        echo ''
        echo 'File count and sizes:'
        for file in /tmp/*.pcap; do
            if [ -f \"\$file\" ]; then
                filename=\$(basename \"\$file\")
                size=\$(stat -c%s \"\$file\" 2>/dev/null || echo 'unknown')
                echo \"  \$filename: \$size bytes\"
            fi
        done
    else
        echo 'No pcap files found in /tmp/'
    fi
"

# Check if tcpdump is currently running
echo ""
TCPDUMP_PIDS=$(docker exec "$CONTAINER_NAME" sh -c "pgrep tcpdump" 2>/dev/null || true)
if [ -n "$TCPDUMP_PIDS" ]; then
    echo "Active tcpdump processes: $TCPDUMP_PIDS"
else
    echo "No tcpdump processes currently running"
fi

# Show current capture file if it exists
if [ -f /tmp/current_capture.txt ]; then
    CURRENT_FILE=$(cat /tmp/current_capture.txt)
    echo "Current/last capture file: $CURRENT_FILE"
fi

echo ""
echo "Commands:"
echo "  Copy a file: ./scripts/copy_pcap.sh <filename>"
echo "  Start capture: ./scripts/start_tcpdump.sh [filename]"
echo "  Stop capture: ./scripts/stop_tcpdump.sh"