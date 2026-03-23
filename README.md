# killport

Kill processes by port number. Simple, cross-platform (macOS / Linux), interactive CLI tool.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chungmanpark/killport/main/install.sh | bash
source ~/.zshrc
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/chungmanpark/killport/main/uninstall.sh | bash
source ~/.zshrc
```

## Usage

```bash
killport 3000                        # Kill process on port 3000
killport 3000 8080 5432              # Kill multiple ports
killport -y 3000                     # Kill without confirmation
killport --dry-run 3000              # Show process info only (no kill)
killport --dry-run 3000 8080         # Dry-run on multiple ports
killport --timeout=5 3000            # Wait 5s before escalating to SIGKILL
killport --signal=HUP 3000           # Send SIGHUP instead of SIGTERM
killport --version                   # Show version
killport --update                    # Self-update to latest version
killport --help                      # Show help
```

## Options

| Option | Description |
|--------|-------------|
| `-y`, `--yes` | Kill without confirmation prompt |
| `--dry-run` | Show process info without killing |
| `--timeout=N` | Timeout in seconds before SIGKILL (default: 3) |
| `--signal=SIG` | Signal to send (default: 15/SIGTERM) |
| `--update` | Update to the latest version |
| `-v`, `--version` | Show version |
| `-h`, `--help` | Show help |

## How it works

1. Finds the PID(s) listening on the given port(s)
2. Shows process name and command for each PID
3. Asks for confirmation (unless `-y` is used)
4. Sends `SIGTERM` (or custom signal) and waits up to timeout seconds
5. If the process is still alive, escalates to `SIGKILL`

## Platform support

- **macOS**: Uses `lsof` to find processes
- **Linux**: Uses `ss` to find processes, falls back to `lsof`
