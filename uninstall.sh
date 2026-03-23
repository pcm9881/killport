#!/bin/bash

set -e

INSTALL_DIR="${KILLPORT_HOME:-$HOME/.killport}"

detect_shell_rc() {
  local shell_name
  shell_name="$(basename "$SHELL")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    fish) echo "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/killport.fish" ;;
    *)    echo "$HOME/.zshrc" ;;
  esac
}

SHELL_RC=$(detect_shell_rc)

# Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
  echo "[warn] killport is not installed."
  exit 0
fi

# Remove install directory
rm -rf "$INSTALL_DIR"

# Remove source line from shell rc (preserve permissions)
if [ -f "$SHELL_RC" ]; then
  orig_perms=$(stat -f '%Lp' "$SHELL_RC" 2>/dev/null || stat -c '%a' "$SHELL_RC" 2>/dev/null)
  tmp=$(mktemp)
  grep -vF "source \"$INSTALL_DIR/killport.sh\"" "$SHELL_RC" \
    | grep -vxF "# killport" \
    > "$tmp" || true
  chmod "$orig_perms" "$tmp" 2>/dev/null || true
  mv "$tmp" "$SHELL_RC"
fi

# Also clean up legacy marker-based installs
if grep -q "# >>> killport >>>" "$SHELL_RC" 2>/dev/null; then
  orig_perms=$(stat -f '%Lp' "$SHELL_RC" 2>/dev/null || stat -c '%a' "$SHELL_RC" 2>/dev/null)
  tmp=$(mktemp)
  awk '/# >>> killport >>>/{skip=1; next} /# <<< killport <<</{skip=0; next} !skip' "$SHELL_RC" > "$tmp"
  chmod "$orig_perms" "$tmp" 2>/dev/null || true
  mv "$tmp" "$SHELL_RC"
fi

echo "[ok] killport has been uninstalled."
echo "     Apply now with: source $SHELL_RC"
