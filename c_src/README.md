# C NIF Dependencies

## LZ4 Compression Library

The LZ4 NIF wrapper requires the official lz4 library to be installed on your system.

### Installation

**macOS (Homebrew)**:
```bash
brew install lz4
```

**macOS (Nix)**:
```bash
nix-env -iA nixpkgs.lz4
```

**Ubuntu/Debian**:
```bash
sudo apt-get install liblz4-dev
```

**Fedora/RHEL**:
```bash
sudo dnf install lz4-devel
```

### Verification

After installation, verify the library is available:
```bash
pkg-config --modversion liblz4
```

### Building

Once lz4 is installed, compile the project:
```bash
rebar3 compile
```

The NIF will be built automatically and placed in `priv/clickhouse_erl_lz4_nif.so`.
