#!/usr/bin/env bash
set -e

# clean.sh: A cleanup utility for the cloud_gpu project.
#
# - Removes aliases from shell RC file (~/.zshrc or ~/.bashrc)
# - Removes the .env configuration file.

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
  zsh)  SHELL_RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bashrc" ;;
  *)    SHELL_RC="$HOME/.profile" ;;
esac

# --- Step 2: Remove aliases from shell RC file ---
if [[ -f "$SHELL_RC" ]] && grep -qF "$ALIAS_BLOCK_START" "$SHELL_RC" 2>/dev/null; then
  if ask_yes_no "🗑️  Remove cloud_gpu aliases from $SHELL_RC? [y/N]"; then
    # macOS sed requires an empty string argument for the -i flag to edit in-place
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "/$ALIAS_BLOCK_START/,/$ALIAS_BLOCK_END/d" "$SHELL_RC"
    else
      sed -i "/$ALIAS_BLOCK_START/,/$ALIAS_BLOCK_END/d" "$SHELL_RC"
    fi
    echo "✅ Aliases removed from $SHELL_RC."
    echo "💡 Run 'source $SHELL_RC' to update your current terminal session."
  else
    echo "ℹ️  Skipped alias removal."
  fi
else
  echo "ℹ️  No cloud_gpu aliases found in $SHELL_RC."
fi

# --- Step 3: Remove the .env configuration file ---
if [[ -f "$CONFIG_FILE" ]]; then
  if ask_yes_no "🗑️  Remove configuration file '$CONFIG_FILE'? [y/N]"; then
    rm -f "$CONFIG_FILE"
    echo "✅ Configuration file removed."
  else
    echo "ℹ️  Skipped configuration file removal."
  fi
else
  echo "ℹ️  No $CONFIG_FILE found to remove."
fi

echo "🎉 Cleanup complete."