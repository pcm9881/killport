#!/bin/bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/chungmanpark/killport/main"
INSTALL_DIR="${KILLPORT_HOME:-$HOME/.killport}"
SOURCE_LINE="# killport
[ -f \"$INSTALL_DIR/killport.sh\" ] && source \"$INSTALL_DIR/killport.sh\""

# ── detect_shell_rc ──────────────────────────────────────────────────────────
# NOTE: This function is duplicated in install.sh and uninstall.sh.
# Both copies must be kept in sync. Each script must remain self-contained
# for curl-pipe installation (curl ... | bash).
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

# Check if already installed (allow upgrade)
if [ -f "$INSTALL_DIR/killport.sh" ]; then
  current_version=$(grep '^KILLPORT_VERSION=' "$INSTALL_DIR/killport.sh" | head -1 | cut -d'"' -f2)
  echo "[info] killport $current_version is already installed. Upgrading..."
fi

echo "[install] Installing killport..."
echo "          Directory : $INSTALL_DIR"
echo "          Shell rc  : $SHELL_RC"

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download killport.sh to install directory
tmp=$(mktemp)
if ! curl -fsSL "$REPO_RAW/killport.sh" -o "$tmp"; then
  echo "[error] Failed to download killport.sh" >&2
  rm -f "$tmp"
  exit 1
fi

# Verify download integrity: size check
file_size=$(wc -c < "$tmp")
if [ "$file_size" -lt 1000 ]; then
  echo "[error] Downloaded file is too small (${file_size} bytes, expected >1000)" >&2
  rm -f "$tmp"
  exit 1
fi

# Verify the download contains the expected function
if ! grep -q 'killport()' "$tmp"; then
  echo "[error] Downloaded file is invalid (missing killport function)" >&2
  rm -f "$tmp"
  exit 1
fi

# Preserve permissions if upgrading, otherwise set sensible default
target="$INSTALL_DIR/killport.sh"
if [ -f "$target" ]; then
  orig_perms=$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null || echo "644")
  chmod "$orig_perms" "$tmp" 2>/dev/null || true
else
  chmod 644 "$tmp" 2>/dev/null || true
fi

mv "$tmp" "$target"

# Add source line to shell rc (only if not already present)
if ! grep -qF "source \"$INSTALL_DIR/killport.sh\"" "$SHELL_RC" 2>/dev/null; then
  {
    echo ""
    echo "$SOURCE_LINE"
  } >> "$SHELL_RC"
fi

new_version=$(grep '^KILLPORT_VERSION=' "$INSTALL_DIR/killport.sh" | head -1 | cut -d'"' -f2)

echo ""
echo "[ok] Installed killport $new_version successfully!"
echo "     Apply now with:"
echo ""
echo "     source $SHELL_RC"
echo ""
echo "     Usage: killport 3000"
echo "            killport -y 3000 8080"
echo "            killport --dry-run 3000"
