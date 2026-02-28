#!/bin/bash

# Stop tcpdump in ClickHouse container
# Usage: ./scripts/stop_tcpdump.sh

set -e

CONTAINER_NAME="clickhouse"

echo "Stopping tcpdump in container '$CONTAINER_NAME'..."

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '$CONTAINER_NAME' is not running"
    exit 1
fi

# Find and kill tcpdump processes
TCPDUMP_PIDS=$(docker exec "$CONTAINER_NAME" sh -c "pgrep tcpdump" 2>/dev/null || true)

if [ -z "$TCPDUMP_PIDS" ]; then
    echo "No tcpdump processes found running"
    exit 0
fi

echo "Found tcpdump processes: $TCPDUMP_PIDS"

# Kill all tcpdump processes
for PID in $TCPDUMP_PIDS; do
    echo "Stopping tcpdump process $PID..."
    docker exec "$CONTAINER_NAME" kill "$PID" 2>/dev/null || true
done

# Wait a moment for processes to stop
sleep 1

# Verify they're stopped
REMAINING_PIDS=$(docker exec "$CONTAINER_NAME" sh -c "pgrep tcpdump" 2>/dev/null || true)
if [ -z "$REMAINING_PIDS" ]; then
    echo "All tcpdump processes stopped successfully"
else
    echo "Warning: Some tcpdump processes may still be running: $REMAINING_PIDS"
fi

# Show available pcap files
echo ""
echo "Available pcap files in container:"
docker exec "$CONTAINER_NAME" ls -la /tmp/*.pcap 2>/dev/null || echo "No pcap files found"

# Show current capture file if it exists
if [ -f /tmp/current_capture.txt ]; then
    CURRENT_FILE=$(cat /tmp/current_capture.txt)
    echo ""
    echo "Last capture file: $CURRENT_FILE"
    echo "To copy it, run: ./scripts/copy_pcap.sh $CURRENT_FILE"
fi