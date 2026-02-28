# ClickHouse Protocol Debugging Scripts

This directory contains bash scripts for capturing and analyzing network traffic between the Erlang client and ClickHouse server. These tools are essential for debugging protocol implementation issues.

## Scripts Overview

### `start_tcpdump.sh`
Starts packet capture in the ClickHouse container.

```bash
# Start capture with auto-generated filename
./scripts/start_tcpdump.sh

# Start capture with custom filename
./scripts/start_tcpdump.sh my_test_capture.pcap
```

**Features:**
- Captures all traffic on port 9000 (ClickHouse native protocol)
- Runs tcpdump in background inside the container
- Auto-generates timestamped filenames
- Tracks current capture for easy reference

### `stop_tcpdump.sh`
Stops all running tcpdump processes in the container.

```bash
./scripts/stop_tcpdump.sh
```

**Features:**
- Finds and kills all tcpdump processes
- Shows available pcap files
- Displays the last capture filename for easy copying

### `copy_pcap.sh`
Copies pcap files from container to local filesystem.

```bash
# Copy with same filename
./scripts/copy_pcap.sh capture_20240105_143022.pcap

# Copy with different local name
./scripts/copy_pcap.sh capture_20240105_143022.pcap local_analysis.pcap

# Copy without .pcap extension (auto-added)
./scripts/copy_pcap.sh capture_20240105_143022
```

**Features:**
- Auto-adds .pcap extension if missing
- Shows file size and basic info
- Provides analysis suggestions (tcpdump, Wireshark)

### `list_pcaps.sh`
Lists all pcap files in the container with details.

```bash
./scripts/list_pcaps.sh
```

**Features:**
- Shows file sizes and timestamps
- Displays active tcpdump processes
- Shows current/last capture filename
- Provides command suggestions

### `clean_pcaps.sh`
Removes old pcap files from the container.

```bash
# Interactive mode (asks for confirmation)
./scripts/clean_pcaps.sh

# Force mode (no confirmation)
./scripts/clean_pcaps.sh --force
```

**Features:**
- Lists files before deletion
- Stops running tcpdump processes first
- Interactive confirmation (unless --force)
- Cleans up tracking files

## Typical Workflow

### 1. Debug a Protocol Issue

```bash
# Start capturing
./scripts/start_tcpdump.sh debug_select_query

# Run your test or reproduce the issue
rebar3 eunit --module=clickhouse_erl_query_integration_tests

# Stop capturing
./scripts/stop_tcpdump.sh

# Copy the capture file
./scripts/copy_pcap.sh debug_select_query.pcap

# Analyze with tcpdump or Wireshark
tcpdump -r debug_select_query.pcap -A
```

### 2. Compare Working vs Broken Packets

```bash
# Capture working scenario
./scripts/start_tcpdump.sh working_case
# ... run working test ...
./scripts/stop_tcpdump.sh

# Capture broken scenario  
./scripts/start_tcpdump.sh broken_case
# ... run failing test ...
./scripts/stop_tcpdump.sh

# Copy both files
./scripts/copy_pcap.sh working_case.pcap
./scripts/copy_pcap.sh broken_case.pcap

# Compare in Wireshark or with diff tools
```

### 3. Clean Up After Testing

```bash
# List what's accumulated
./scripts/list_pcaps.sh

# Clean up old captures
./scripts/clean_pcaps.sh
```

## Analysis Tips

### Using tcpdump
```bash
# Basic packet info
tcpdump -r capture.pcap

# Show packet contents in ASCII
tcpdump -r capture.pcap -A

# Filter by specific packets
tcpdump -r capture.pcap 'port 9000'

# Show hex dump
tcpdump -r capture.pcap -X
```

### Using Wireshark
1. Open the pcap file in Wireshark
2. Filter by `tcp.port == 9000` to see only ClickHouse traffic
3. Right-click packets → Follow → TCP Stream to see the conversation
4. Use "Decode As" if needed to interpret custom protocols

### Comparing Packets
```bash
# Extract just the data bytes for comparison
tcpdump -r working.pcap -X | grep -E "^\s+0x" > working_hex.txt
tcpdump -r broken.pcap -X | grep -E "^\s+0x" > broken_hex.txt
diff working_hex.txt broken_hex.txt
```

## Troubleshooting

### Container Not Running
```bash
# Start ClickHouse container
docker-compose up -d

# Check container status
docker ps | grep clickhouse
```

### Permission Issues
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Check Docker permissions
docker exec clickhouse whoami
```

### Large Capture Files
```bash
# Check file sizes before copying
./scripts/list_pcaps.sh

# Clean up old files regularly
./scripts/clean_pcaps.sh --force
```

## Integration with Tests

These scripts work well with the existing test suite:

```bash
# Capture during integration tests
./scripts/start_tcpdump.sh integration_test
rebar3 eunit --module=clickhouse_erl_query_integration_tests
./scripts/stop_tcpdump.sh
./scripts/copy_pcap.sh integration_test.pcap

# Capture during property tests
./scripts/start_tcpdump.sh property_test
rebar3 eunit --module=clickhouse_erl_connection_query_property_tests
./scripts/stop_tcpdump.sh
./scripts/copy_pcap.sh property_test.pcap
```

This allows you to see exactly what packets are being exchanged during test execution, making it much easier to debug protocol implementation issues.