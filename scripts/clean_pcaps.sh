#!/bin/bash

# Clean up old pcap files from ClickHouse container
# Usage: ./scripts/clean_pcaps.sh [--force]

set -e

CONTAINER_NAME="clickhouse"
FORCE_MODE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

echo "Cleaning pcap files from container '$CONTAINER_NAME'..."

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '$CONTAINER_NAME' is not running"
    exit 1
fi

# List current files
PCAP_FILES=$(docker exec "$CONTAINER_NAME" sh -c "ls /tmp/*.pcap 2>/dev/null || true")

if [ -z "$PCAP_FILES" ]; then
    echo "No pcap files found to clean"
    exit 0
fi

echo ""
echo "Found pcap files:"
docker exec "$CONTAINER_NAME" ls -lah /tmp/*.pcap

if [ "$FORCE_MODE" = false ]; then
    echo ""
    read -p "Are you sure you want to delete all pcap files? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
fi

# Stop any running tcpdump processes first
echo ""
echo "Stopping any running tcpdump processes..."
TCPDUMP_PIDS=$(docker exec "$CONTAINER_NAME" sh -c "pgrep tcpdump" 2>/dev/null || true)
if [ -n "$TCPDUMP_PIDS" ]; then
    for PID in $TCPDUMP_PIDS; do
        echo "Stopping tcpdump process $PID..."
        docker exec "$CONTAINER_NAME" kill "$PID" 2>/dev/null || true
    done
    sleep 1
fi

# Remove pcap files
echo "Removing pcap files..."
docker exec "$CONTAINER_NAME" sh -c "rm -f /tmp/*.pcap"

# Clean up local tracking file
rm -f /tmp/current_capture.txt

echo "All pcap files cleaned successfully"