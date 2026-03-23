#!/usr/bin/env bash
# killport - Kill process running on a given port
# https://github.com/chungmanpark/killport
# shellcheck shell=bash

KILLPORT_VERSION="1.5.1"

# ── Color support ────────────────────────────────────────────────────────────

_killport_setup_colors() {
  if [ -t 1 ] && [ -t 2 ] && command -v tput &>/dev/null \
    && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    _KP_RED=$(tput setaf 1)
    _KP_GREEN=$(tput setaf 2)
    _KP_YELLOW=$(tput setaf 3)
    _KP_CYAN=$(tput setaf 6)
    _KP_BOLD=$(tput bold)
    _KP_RESET=$(tput sgr0)
  else
    _KP_RED="" _KP_GREEN="" _KP_YELLOW="" _KP_CYAN="" _KP_BOLD="" _KP_RESET=""
  fi
}

# ── Signal helpers ───────────────────────────────────────────────────────────

# Validate signal name or number
_killport_valid_signal() {
  local sig="$1"

  # Strip SIG prefix if present (e.g., SIGTERM -> TERM)
  sig="${sig#SIG}"

  # Numeric: must be 1-31
  if [[ "$sig" =~ ^[0-9]+$ ]]; then
    [ "$sig" -ge 1 ] && [ "$sig" -le 31 ]
    return $?
  fi

  # Named: check against kill -l output
  kill -l "$sig" &>/dev/null
  return $?
}

# Normalize signal: strip SIG prefix, uppercase
_killport_normalize_signal() {
  local sig="$1"
  sig="${sig#SIG}"
  if ! [[ "$sig" =~ ^[0-9]+$ ]]; then
    sig=$(echo "$sig" | tr '[:lower:]' '[:upper:]')
  fi
  echo "$sig"
}

# Check if a signal is SIGTERM (numeric 15 or name TERM)
_killport_is_sigterm() {
  local sig="$1"
  [ "$sig" = "15" ] || [ "$sig" = "TERM" ]
}

# ── Argument validation helpers ──────────────────────────────────────────────

_killport_validate_timeout() {
  local val="$1"
  if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 1 ]; then
    echo "${_KP_RED}[error]${_KP_RESET} --timeout must be a positive integer" >&2
    return 2
  fi
}

_killport_validate_signal() {
  local val="$1"
  if ! _killport_valid_signal "$val"; then
    echo "${_KP_RED}[error]${_KP_RESET} Unknown signal: $val" >&2
    echo "${_KP_CYAN}[hint]${_KP_RESET}  Use a number (1-31) or name (TERM, HUP, KILL, ...)" >&2
    return 2
  fi
}

# ── Exit code priority ──────────────────────────────────────────────────────
# Severity order: 126 (permission) > 2 (invalid args) > 1 (not found) > 130 (cancelled)

_killport_exit_priority() {
  case "$1" in
    126) echo 4 ;;
    2)   echo 3 ;;
    1)   echo 2 ;;
    130) echo 1 ;;
    0)   echo 0 ;;
    *)   echo 2 ;;
  esac
}

_killport_worse_exit() {
  local cur_pri new_pri
  cur_pri=$(_killport_exit_priority "$1")
  new_pri=$(_killport_exit_priority "$2")
  if [ "$new_pri" -gt "$cur_pri" ]; then
    echo "$2"
  else
    echo "$1"
  fi
}

# ── Find PIDs listening on a port (cross-platform) ──────────────────────────

_killport_find_pids() {
  local port="$1"
  local proto="${2:-tcp}"

  # Linux: prefer ss for better performance
  if [ "$(uname -s)" = "Linux" ] && command -v ss &>/dev/null; then
    local flag
    flag=$( [ "$proto" = "udp" ] && echo "-ulnp" || echo "-tlnp" )
    ss "$flag" "sport = :$port" 2>/dev/null \
      | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
      | sort -u
    return
  fi

  # Fallback: lsof (macOS, Linux without ss, others)
  if [ "$proto" = "udp" ]; then
    lsof -ti "udp:$port" 2>/dev/null | sort -u
  else
    lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null | sort -u
  fi
}

# ── Main function ────────────────────────────────────────────────────────────

killport() {
  _killport_setup_colors

  local dry_run=false
  local force=false
  local quiet=false
  local timeout=3
  local signal=15
  local proto="tcp"
  local ports=()
  local pids proc_name proc_cmd waited
  local exit_code=0
  local opts_done=false

  # Parse arguments
  while [ $# -gt 0 ]; do
    if $opts_done; then
      ports+=("$1")
      shift
      continue
    fi

    case "$1" in
      --)
        opts_done=true
        shift
        continue
        ;;
      --help)
        echo "Usage: killport [options] <port> [port2] [port3] ..."
        echo ""
        echo "Options:"
        echo "  -y, --yes, --force  Kill without confirmation prompt"
        echo "  --dry-run           Show process info without killing"
        echo "  --timeout=N         Timeout in seconds before SIGKILL (default: 3)"
        echo "  --signal=SIG        Signal to send (default: 15/SIGTERM)"
        echo "  --udp               Target UDP instead of TCP (default: TCP)"
        echo "  -q, --quiet         Suppress all output (exit code only; implies --force)"
        echo "  --update            Update killport to the latest version"
        echo "  --version, -v       Show version"
        echo "  --help, -h          Show this help"
        return 0
        ;;
      --version)
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
      --yes|--force)
        force=true
        ;;
      --udp)
        proto="udp"
        ;;
      --quiet)
        quiet=true
        ;;
      --timeout=*)
        timeout="${1#--timeout=}"
        _killport_validate_timeout "$timeout" || return $?
        ;;
      --timeout)
        if [ $# -lt 2 ] || [[ "$2" == -* ]]; then
          echo "${_KP_RED}[error]${_KP_RESET} --timeout requires a value" >&2
          return 2
        fi
        timeout="$2"
        shift
        _killport_validate_timeout "$timeout" || return $?
        ;;
      --signal=*)
        signal="${1#--signal=}"
        _killport_validate_signal "$signal" || return $?
        signal=$(_killport_normalize_signal "$signal")
        ;;
      --signal)
        if [ $# -lt 2 ] || [[ "$2" == -* ]]; then
          echo "${_KP_RED}[error]${_KP_RESET} --signal requires a value" >&2
          return 2
        fi
        signal="$2"
        shift
        _killport_validate_signal "$signal" || return $?
        signal=$(_killport_normalize_signal "$signal")
        ;;
      -*)
        # Handle combined short options (e.g., -yv, -hy)
        local shorts="${1#-}"
        local i=0
        while [ "$i" -lt "${#shorts}" ]; do
          local c="${shorts:$i:1}"
          case "$c" in
            y) force=true ;;
            q) quiet=true ;;
            v) echo "killport $KILLPORT_VERSION"; return 0 ;;
            h)
              killport --help
              return 0
              ;;
            *)
              echo "${_KP_RED}[error]${_KP_RESET} Unknown option: -$c" >&2
              echo "${_KP_CYAN}[hint]${_KP_RESET}  Try 'killport --help' for usage" >&2
              return 2
              ;;
          esac
          i=$((i + 1))
        done
        ;;
      *)
        ports+=("$1")
        ;;
    esac
    shift
  done

  if [ ${#ports[@]} -eq 0 ]; then
    echo "Usage: killport [options] <port> [port2] ..." >&2
    echo "Try 'killport --help' for more information." >&2
    return 2
  fi

  for port in "${ports[@]}"; do
    # Validate: must be numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      echo "${_KP_YELLOW}[warn]${_KP_RESET} '$port' is not a valid port number" >&2
      exit_code=$(_killport_worse_exit "$exit_code" 2)
      continue
    fi

    # Normalize: strip leading zeros
    port=$((10#$port))

    # Validate: must be in range 1-65535
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      echo "${_KP_YELLOW}[warn]${_KP_RESET} '$port' is out of range (1-65535)" >&2
      exit_code=$(_killport_worse_exit "$exit_code" 2)
      continue
    fi

    pids=$(_killport_find_pids "$port" "$proto")

    if [ -z "$pids" ]; then
      $quiet || echo "${_KP_YELLOW}[miss]${_KP_RESET} No process found on $(echo "$proto" | tr '[:lower:]' '[:upper:]') port $port" >&2
      exit_code=$(_killport_worse_exit "$exit_code" 1)
      continue
    fi

    for pid in $pids; do
      # Self-kill protection: check $$ (shell PID), $PPID, and $BASHPID if available
      local self_pid="${BASHPID:-$$}"
      if [ "$pid" -eq "$self_pid" ] 2>/dev/null \
        || [ "$pid" -eq "$$" ] 2>/dev/null \
        || [ "$pid" -eq "$PPID" ] 2>/dev/null; then
        $quiet || echo "        ${_KP_YELLOW}[skip]${_KP_RESET} PID $pid is the current shell (refusing to self-kill)" >&2
        continue
      fi

      proc_name=$(ps -p "$pid" -o comm= 2>/dev/null)
      proc_cmd=$(ps -p "$pid" -o args= 2>/dev/null)

      if ! $quiet; then
        echo ""
        echo "${_KP_CYAN}[found]${_KP_RESET} $(echo "$proto" | tr '[:lower:]' '[:upper:]') port $port -> ${_KP_BOLD}PID $pid${_KP_RESET}"
        echo "        Process : $proc_name"
        echo "        Command : $proc_cmd"
      fi

      if $dry_run; then
        $quiet || echo "        ${_KP_CYAN}(dry-run)${_KP_RESET} skipped"
        continue
      fi

      if ! $force; then
        if $quiet; then
          # quiet mode cannot prompt interactively; imply --force
          :
        else
          echo -n "        Kill this process? [y/N] "
          read -r answer
          if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "        Skipped PID $pid"
            exit_code=$(_killport_worse_exit "$exit_code" 130)
            continue
          fi
        fi
      fi

      # Re-verify PID still owns this port (TOCTOU mitigation)
      local recheck_pids
      recheck_pids=$(_killport_find_pids "$port" "$proto")
      if ! echo "$recheck_pids" | grep -qw "$pid"; then
        $quiet || echo "        ${_KP_YELLOW}[skip]${_KP_RESET} PID $pid no longer on port $port (process changed)" >&2
        continue
      fi

      # Attempt kill with specified signal
      if ! kill -"$signal" "$pid" 2>/dev/null; then
        if [ "$(id -u)" -ne 0 ]; then
          $quiet || echo "        ${_KP_RED}[error]${_KP_RESET} Permission denied for PID $pid" >&2
          $quiet || echo "        ${_KP_CYAN}[hint]${_KP_RESET}  Try: sudo kill -$signal $pid" >&2
          exit_code=$(_killport_worse_exit "$exit_code" 126)
        else
          $quiet || echo "        ${_KP_RED}[error]${_KP_RESET} Failed to send signal $signal to PID $pid" >&2
          exit_code=$(_killport_worse_exit "$exit_code" 1)
        fi
        continue
      fi

      $quiet || echo -n "        Signal $signal sent, waiting..."

      # Poll for process exit (1s intervals, up to $timeout seconds)
      waited=0
      while [ "$waited" -lt "$timeout" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
          $quiet || echo " done"
          $quiet || echo "        ${_KP_GREEN}[ok]${_KP_RESET} Killed PID $pid (signal $signal)"
          break
        fi
        sleep 1
        waited=$((waited + 1))
      done

      # If still alive, escalate to SIGKILL (only when using SIGTERM)
      if kill -0 "$pid" 2>/dev/null; then
        if ! _killport_is_sigterm "$signal"; then
          $quiet || echo " timeout"
          $quiet || echo "        ${_KP_YELLOW}[warn]${_KP_RESET} Process $pid did not exit within ${timeout}s" >&2
          exit_code=$(_killport_worse_exit "$exit_code" 1)
        else
          $quiet || echo " timeout"
          $quiet || echo -n "        Escalating to SIGKILL..."
          if kill -9 "$pid" 2>/dev/null; then
            # Verify process actually exited after SIGKILL
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
              $quiet || echo " ${_KP_RED}failed${_KP_RESET}" >&2
              $quiet || echo "        ${_KP_RED}[error]${_KP_RESET} PID $pid still alive after SIGKILL (zombie or kernel-blocked)" >&2
              exit_code=$(_killport_worse_exit "$exit_code" 1)
            else
              $quiet || echo " done"
              $quiet || echo "        ${_KP_GREEN}[ok]${_KP_RESET} Killed PID $pid (SIGKILL)"
            fi
          else
            $quiet || echo " ${_KP_RED}failed${_KP_RESET}" >&2
            $quiet || echo "        ${_KP_RED}[error]${_KP_RESET} Failed to kill PID $pid" >&2
            exit_code=$(_killport_worse_exit "$exit_code" 1)
          fi
        fi
      fi
    done
  done

  return "$exit_code"
}

# ── Self-update ──────────────────────────────────────────────────────────────

killport_update() {
  _killport_setup_colors

  local repo_raw="https://raw.githubusercontent.com/chungmanpark/killport/main"
  local install_dir="${KILLPORT_HOME:-$HOME/.killport}"
  local target="$install_dir/killport.sh"

  echo "${_KP_CYAN}[update]${_KP_RESET} Downloading latest killport..."

  # Verify write permissions
  if [ -f "$target" ] && [ ! -w "$target" ]; then
    echo "${_KP_RED}[error]${_KP_RESET} No write permission to $target" >&2
    echo "${_KP_CYAN}[hint]${_KP_RESET}  Try running with appropriate permissions" >&2
    return 126
  fi

  if [ ! -d "$install_dir" ]; then
    echo "${_KP_RED}[error]${_KP_RESET} Install directory not found: $install_dir" >&2
    echo "${_KP_CYAN}[hint]${_KP_RESET}  Run the install script first" >&2
    return 1
  fi

  if [ ! -w "$install_dir" ]; then
    echo "${_KP_RED}[error]${_KP_RESET} No write permission to $install_dir" >&2
    return 126
  fi

  local tmp orig_perms
  tmp=$(mktemp)
  if ! curl -fsSL "$repo_raw/killport.sh" -o "$tmp" 2>/dev/null; then
    echo "${_KP_RED}[error]${_KP_RESET} Failed to download update" >&2
    rm -f "$tmp"
    return 1
  fi

  # Verify download integrity: size check
  local file_size
  file_size=$(wc -c < "$tmp")
  if [ "$file_size" -lt 1000 ]; then
    echo "${_KP_RED}[error]${_KP_RESET} Downloaded file is too small (${file_size} bytes, expected >1000)" >&2
    rm -f "$tmp"
    return 1
  fi

  # Verify download integrity: function check
  if ! grep -q 'killport()' "$tmp"; then
    echo "${_KP_RED}[error]${_KP_RESET} Downloaded file is invalid (missing killport function)" >&2
    rm -f "$tmp"
    return 1
  fi

  local new_version
  new_version=$(grep '^KILLPORT_VERSION=' "$tmp" | head -1 | cut -d'"' -f2)

  if [ "$new_version" = "$KILLPORT_VERSION" ]; then
    echo "${_KP_GREEN}[update]${_KP_RESET} Already up to date ($KILLPORT_VERSION)"
    rm -f "$tmp"
    return 0
  fi

  # Semver comparison: prevent downgrade
  local higher
  higher=$(printf '%s\n%s\n' "$KILLPORT_VERSION" "$new_version" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  if [ "$higher" = "$KILLPORT_VERSION" ]; then
    echo "${_KP_YELLOW}[update]${_KP_RESET} Local version ($KILLPORT_VERSION) is newer than remote ($new_version), skipping"
    rm -f "$tmp"
    return 0
  fi

  # Preserve original file permissions
  if [ -f "$target" ]; then
    orig_perms=$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null || echo "644")
    chmod "$orig_perms" "$tmp" 2>/dev/null || true
  fi

  mv "$tmp" "$target"
  echo "${_KP_GREEN}[update]${_KP_RESET} Updated: $KILLPORT_VERSION -> $new_version"

  # Auto-source the updated file
  # shellcheck disable=SC1090
  source "$target"
  echo "         Applied immediately (killport $new_version is now active)."
  return 0
}

# ── Shell completions ────────────────────────────────────────────────────────

# Bash completion (compatible with bash 3.2+)
_killport_bash_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local opts="--help --version --update --dry-run --yes --force --quiet --timeout= --signal= --udp -y -q -v -h"

  if [[ "$cur" == -* ]]; then
    COMPREPLY=()
    while IFS= read -r line; do
      COMPREPLY+=("$line")
    done < <(compgen -W "$opts" -- "$cur")
  fi
}

# Zsh completion
_killport_zsh_completion() {
  local -a options
  options=(
    '--help[Show help]'
    '-h[Show help]'
    '--version[Show version]'
    '-v[Show version]'
    '--update[Update to latest version]'
    '--dry-run[Show process info without killing]'
    '--yes[Kill without confirmation]'
    '-y[Kill without confirmation]'
    '--force[Kill without confirmation]'
    '--quiet[Suppress all output (implies --force)]'
    '-q[Suppress all output (implies --force)]'
    '--timeout=[Timeout before SIGKILL (seconds)]:seconds:'
    '--signal=[Signal to send]:signal:(TERM HUP INT QUIT KILL USR1 USR2)'
    '--udp[Target UDP instead of TCP]'
  )
  # shellcheck disable=SC2128
  _arguments -s "${options[@]}" '*:port:'
}

# Register completions
if [ -n "$BASH_VERSION" ]; then
  complete -F _killport_bash_completion killport
elif [ -n "$ZSH_VERSION" ]; then
  compdef _killport_zsh_completion killport 2>/dev/null || true
fi
