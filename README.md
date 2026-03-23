# killport

Kill processes by port number. Simple, cross-platform (macOS / Linux), interactive CLI tool.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chungmanpark/killport/main/install.sh | bash
```

Then reload your shell:

```bash
# zsh
source ~/.zshrc

# bash
source ~/.bashrc
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/chungmanpark/killport/main/uninstall.sh | bash
```

Then reload your shell:

```bash
# zsh
source ~/.zshrc

# bash
source ~/.bashrc
```

## Usage

```bash
killport 3000                        # Kill process on port 3000
killport 3000 8080 5432              # Kill multiple ports
killport -y 3000                     # Kill without confirmation
killport --dry-run 3000              # Show process info only (no kill)
killport --dry-run 3000 8080         # Dry-run on multiple ports
killport --timeout=5 3000            # Wait 5s before escalating to SIGKILL
killport --timeout 5 3000            # Same (space-separated)
killport --signal=HUP 3000           # Send SIGHUP instead of SIGTERM
killport --signal HUP 3000           # Same (space-separated)
killport --udp 3000                  # Kill process on UDP port 3000
killport -q -y 3000                  # Quiet mode (exit code only)
killport -yv                         # Combined short options
killport -- 3000                     # Use -- to end options
killport --version                   # Show version
killport --update                    # Self-update to latest version
killport --help                      # Show help
```

## Options

| Option | Description |
|--------|-------------|
| `-y`, `--yes`, `--force` | Kill without confirmation prompt |
| `--dry-run` | Show process info without killing |
| `--timeout=N` | Timeout in seconds before SIGKILL (default: 3) |
| `--signal=SIG` | Signal to send (default: 15/SIGTERM) |
| `--udp` | Target UDP instead of TCP (default: TCP) |
| `-q`, `--quiet` | Suppress all output (exit code only) |
| `--update` | Update to the latest version |
| `-v`, `--version` | Show version |
| `-h`, `--help` | Show help |
| `--` | End of options (treat remaining args as ports) |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Process not found or kill failed |
| `2` | Invalid arguments (bad port, signal, etc.) |
| `126` | Permission denied |
| `130` | User cancelled |

When multiple ports are processed, the most severe exit code is returned. Severity order (highest to lowest): `126` > `2` > `1` > `130`.

## How it works

1. Finds the PID(s) **listening** on the given port(s)
2. Shows process name and command for each PID
3. Asks for confirmation (unless `-y` is used)
4. Sends `SIGTERM` (or custom signal) and waits up to timeout seconds
5. If the process is still alive, escalates to `SIGKILL`
6. Verifies the process has actually exited after `SIGKILL`

## Features

- **Color output**: Status tags are color-coded for quick scanning
- **Tab completion**: Built-in bash and zsh completions (auto-registered on source)
- **UDP support**: `--udp` flag to target UDP ports
- **Combined short options**: `-yv`, `-hy`, etc.
- **Self-update**: `--update` downloads and applies the latest version immediately

## Platform support

- **macOS**: Uses `lsof` to find processes
- **Linux**: Uses `ss` to find processes, falls back to `lsof`

## License

MIT License. See [LICENSE](LICENSE) for details.
