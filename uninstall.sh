#!/bin/bash

set -e

INSTALL_DIR="${KILLPORT_HOME:-$HOME/.killport}"

detect_shell_rc() {
  local shell_name
  shell_name="$(basename "$SHELL")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    fish)
      echo "[error] Fish shell is not yet supported." >&2
      echo "        See https://github.com/chungmanpark/killport/issues" >&2
      exit 1
      ;;
    *)
      echo "[warn] Unknown shell '$shell_name'. Defaulting to ~/.bashrc" >&2
      echo "       Set SHELL_RC env var to override (e.g., SHELL_RC=~/.profile)" >&2
      echo "$HOME/.bashrc"
      ;;
  esac
}

SHELL_RC="${SHELL_RC:-$(detect_shell_rc)}"

# Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
  echo "[warn] killport is not installed."
  exit 0
fi

# Clean up shell rc (before removing install directory)
if [ -f "$SHELL_RC" ]; then
  orig_perms=$(stat -f '%Lp' "$SHELL_RC" 2>/dev/null || stat -c '%a' "$SHELL_RC" 2>/dev/null || echo "644")
  tmp=$(mktemp)
  awk -v install_dir="$INSTALL_DIR" '
    /# >>> killport >>>/ { skip=1; next }
    /# <<< killport <<</ { skip=0; next }
    skip { next }
    /^# killport$/ { next }
    index($0, "source \"" install_dir "/killport.sh\"") { next }
    { print }
  ' "$SHELL_RC" > "$tmp"
  chmod "$orig_perms" "$tmp" 2>/dev/null || true
  mv "$tmp" "$SHELL_RC"
fi

# Remove install directory
rm -rf "$INSTALL_DIR"

echo "[ok] killport has been uninstalled."
echo "     Apply now with: source $SHELL_RC"
