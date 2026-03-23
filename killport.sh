# killport - Kill process running on a given port
# https://github.com/chungmanpark/killport

KILLPORT_VERSION="1.2.0"

killport() {
  local dry_run=false
  local force=false
  local timeout=3
  local signal=15
  local ports=()

  # Parse arguments (position-independent)
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        echo "Usage: killport [options] <port> [port2] [port3] ..."
        echo ""
        echo "Options:"
        echo "  -y, --yes         Kill without confirmation prompt"
        echo "  --dry-run         Show process info without killing"
        echo "  --timeout=N       Timeout in seconds before SIGKILL (default: 3)"
        echo "  --signal=SIG      Signal to send (default: 15/SIGTERM)"
        echo "  --update          Update killport to the latest version"
        echo "  --version, -v     Show version"
        echo "  --help, -h        Show this help"
        return 0
        ;;
      --version|-v)
        echo "killport $KILLPORT_VERSION"
        return 0
        ;;
      --update)
        killport_update
        return $?
        ;;
      --dry-run)
        dry_run=true
        ;;
      -y|--yes|--force)
        force=true
        ;;
      --timeout=*)
        timeout="${arg#--timeout=}"
        if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -lt 1 ]; then
          echo "[error] --timeout must be a positive integer" >&2
          return 1
        fi
        ;;
      --signal=*)
        signal="${arg#--signal=}"
        ;;
      *)
        ports+=("$arg")
        ;;
    esac
  done

  if [ ${#ports[@]} -eq 0 ]; then
    echo "Usage: killport [options] <port> [port2] ..." >&2
    echo "Try 'killport --help' for more information." >&2
    return 1
  fi

  local has_failure=false

  for port in "${ports[@]}"; do
    # Validate: must be numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      echo "[warn] '$port' is not a valid port number" >&2
      has_failure=true
      continue
    fi

    # Normalize: strip leading zeros
    port=$((10#$port))

    # Validate: must be in range 1-65535
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      echo "[warn] '$port' is out of range (1-65535)" >&2
      has_failure=true
      continue
    fi

    local pids
    pids=$(_killport_find_pids "$port")

    if [ -z "$pids" ]; then
      echo "[miss] No process found on port $port" >&2
      has_failure=true
      continue
    fi

    for pid in $pids; do
      # Self-kill protection
      if [ "$pid" -eq "$$" ] 2>/dev/null || [ "$pid" -eq "$PPID" ] 2>/dev/null; then
        echo "        [skip] PID $pid is the current shell (refusing to self-kill)" >&2
        continue
      fi

      local proc_name proc_cmd
      proc_name=$(ps -p "$pid" -o comm= 2>/dev/null)
      proc_cmd=$(ps -p "$pid" -o args= 2>/dev/null)

      echo ""
      echo "[found] Port $port -> PID $pid"
      echo "        Process : $proc_name"
      echo "        Command : $proc_cmd"

      if $dry_run; then
        echo "        (dry-run) skipped"
        continue
      fi

      if ! $force; then
        echo -n "        Kill this process? [y/N] "
        read -r answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
          echo "        Skipped PID $pid"
          continue
        fi
      fi

      # Attempt kill with specified signal
      if ! kill -"$signal" "$pid" 2>/dev/null; then
        if [ "$(id -u)" -ne 0 ]; then
          echo "        [error] Permission denied for PID $pid" >&2
          echo "        [hint] Try: sudo kill -$signal $pid" >&2
        else
          echo "        [error] Failed to send signal $signal to PID $pid" >&2
        fi
        has_failure=true
        continue
      fi

      echo -n "        Signal $signal sent, waiting..."

      # Poll for process exit (1s intervals, up to $timeout seconds)
      local waited=0
      while [ "$waited" -lt "$timeout" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
          echo " done"
          echo "        [ok] Killed PID $pid (signal $signal)"
          break
        fi
        sleep 1
        waited=$((waited + 1))
      done

      # If still alive, escalate to SIGKILL (only when using default SIGTERM)
      if kill -0 "$pid" 2>/dev/null; then
        if [ "$signal" != "15" ]; then
          echo " timeout"
          echo "        [warn] Process $pid did not exit within ${timeout}s" >&2
          has_failure=true
        else
          echo " timeout"
          echo -n "        Escalating to SIGKILL..."
          if kill -9 "$pid" 2>/dev/null; then
            echo " done"
            echo "        [ok] Killed PID $pid (SIGKILL)"
          else
            echo " failed" >&2
            echo "        [error] Failed to kill PID $pid" >&2
            has_failure=true
          fi
        fi
      fi
    done
  done

  if $has_failure; then
    return 1
  fi
  return 0
}

# Find PIDs listening on a port (cross-platform)
_killport_find_pids() {
  local port="$1"
  case "$(uname -s)" in
    Darwin)
      lsof -ti "tcp:$port" 2>/dev/null
      ;;
    Linux)
      if command -v ss &>/dev/null; then
        ss -tlnp "sport = :$port" 2>/dev/null \
          | grep -oP 'pid=\K[0-9]+' \
          | sort -u
      else
        lsof -ti "tcp:$port" 2>/dev/null
      fi
      ;;
    *)
      # Fallback: try lsof
      lsof -ti "tcp:$port" 2>/dev/null
      ;;
  esac
}

# Self-update function
killport_update() {
  local repo_raw="https://raw.githubusercontent.com/chungmanpark/killport/main"
  local install_dir="${KILLPORT_HOME:-$HOME/.killport}"
  local target="$install_dir/killport.sh"

  echo "[update] Downloading latest killport..."

  local tmp
  tmp=$(mktemp)
  if ! curl -fsSL "$repo_raw/killport.sh" -o "$tmp" 2>/dev/null; then
    echo "[error] Failed to download update" >&2
    rm -f "$tmp"
    return 1
  fi

  # Verify download integrity
  if ! grep -q 'killport()' "$tmp"; then
    echo "[error] Downloaded file is invalid (missing killport function)" >&2
    rm -f "$tmp"
    return 1
  fi

  local new_version
  new_version=$(grep '^KILLPORT_VERSION=' "$tmp" | head -1 | cut -d'"' -f2)

  if [ "$new_version" = "$KILLPORT_VERSION" ]; then
    echo "[update] Already up to date ($KILLPORT_VERSION)"
    rm -f "$tmp"
    return 0
  fi

  mv "$tmp" "$target"
  echo "[update] Updated: $KILLPORT_VERSION -> $new_version"
  echo "         Run 'source $target' or open a new terminal to apply."
  return 0
}
