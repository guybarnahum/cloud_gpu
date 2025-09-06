#!/usr/bin/env bash
set -e

# clean.sh: A cleanup utility for the cloud_gpu project.
#
# - Prompts to remove aliases from shell RC file.
# - Prompts to remove the .env configuration file.
#
# Usage: ./clean.sh

# ------------- User-facing variables -------------
CONFIG_FILE=".env"
SHELL_RC=""
ALIAS_BLOCK_START="# >>> cloud_gpu aliases >>>"
ALIAS_BLOCK_END="# <<< cloud_gpu aliases <<<"

# ------------- Helper functions -------------
ask_yes_no() {
  local prompt="$1"
  read -p "$prompt " -n 1 -r; echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

# --- Step 1: Detect shell and set up RC file path ---
SHELL_NAME="$(basename "${SHELL:-}")"
case "$SHELL_NAME" in
  zsh) SHELL_RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bashrc" ;;
  *) SHELL_RC="$HOME/.profile"; echo "⚠️  Unknown shell. Checking $SHELL_RC" ;;
esac

# --- Step 2: Remove aliases from shell RC file ---
if grep -qF "$ALIAS_BLOCK_START" "$SHELL_RC" 2>/dev/null; then
  if ask_yes_no "Remove aliases from $SHELL_RC? [y/N]"; then
    # Use sed to remove the block between the start and end markers.
    # The 'd' command deletes lines in the specified range.
    sed -i '' -e "/$ALIAS_BLOCK_START/,/$ALIAS_BLOCK_END/d" "$SHELL_RC"
    echo "✅ Aliases removed."
  else
    echo "ℹ️  Skipped alias removal."
  fi
fi

# --- Step 3: Remove the .env configuration file ---
if [[ -f "$CONFIG_FILE" ]]; then
  if ask_yes_no "Remove configuration file '$CONFIG_FILE'? [y/N]"; then
    rm -f "$CONFIG_FILE"
    echo "✅ Configuration file removed."
  else
    echo "ℹ️  Skipped configuration file removal."
  fi
fi

echo "🎉 Cleanup complete."