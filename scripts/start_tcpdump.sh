#!/bin/bash

# Start tcpdump in ClickHouse container to capture packets on port 9000
# Usage: ./scripts/start_tcpdump.sh [filename]

set -e

FILENAME=${1:-"capture_$(date +%Y%m%d_%H%M%S)"}
CONTAINER_NAME="clickhouse"

# Add .pcap extension if not present
if [[ "$FILENAME" != *.pcap ]]; then
    FILENAME="${FILENAME}.pcap"
fi

echo "Starting tcpdump in container '$CONTAINER_NAME'..."
echo "Capturing packets on port 9000 to file: $FILENAME"
echo "Press Ctrl+C to stop capture"

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '$CONTAINER_NAME' is not running"
    echo "Start it with: docker-compose up -d"
    exit 1
fi

# Start tcpdump in background and capture its PID
docker exec -d "$CONTAINER_NAME" sh -c "tcpdump -i any -w /tmp/$FILENAME 'port 9000'" > /dev/null

# Get the tcpdump process ID inside the container
TCPDUMP_PID=$(docker exec "$CONTAINER_NAME" sh -c "pgrep tcpdump | tail -1")

if [ -z "$TCPDUMP_PID" ]; then
    echo "Error: Failed to start tcpdump"
    exit 1
fi

echo "tcpdump started with PID $TCPDUMP_PID inside container"
echo "File will be saved as: /tmp/$FILENAME"
echo ""
echo "To stop capture, run: ./scripts/stop_tcpdump.sh"
echo "To copy the file, run: ./scripts/copy_pcap.sh $FILENAME"

# Save the filename for other scripts
echo "$FILENAME" > /tmp/current_capture.txt