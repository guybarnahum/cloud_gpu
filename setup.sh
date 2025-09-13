#!/usr/bin/env bash
set -e

# cloud_setup.sh: Sets up the cloud_gpu project for a chosen cloud provider.
#
# - Installs the required cloud CLI (AWS or gcloud)
# - Prompts for instance details to create a config file
# - Adds aliases to your shell's RC file for easy access
#
# Usage: ./cloud_setup.sh [aws|gcp]

# ------------- User-facing variables -------------
CONFIG_FILE=".env"
SHELL_RC=""
ALIAS_BLOCK_START="# >>> cloud_gpu aliases >>>"
ALIAS_BLOCK_END="# <<< cloud_gpu aliases <<<"
# Get the absolute path of the current directory to use in aliases
SCRIPT_DIR="$(pwd)"

# ------------- Helper functions -------------
have() { command -v "$1" >/dev/null 2>&1; }

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
  *) SHELL_RC="$HOME/.profile"; echo "⚠️  Unknown shell. Aliases will be added to $SHELL_RC" ;;
esac

# --- Step 2: Select cloud provider and set variables ---
if [[ -z "$1" ]]; then
  echo "Please choose a cloud provider (aws or gcp):"
  select provider in "aws" "gcp"; do
    if [[ -n "$provider" ]]; then
      PROVIDER="$provider"
      break
    else
      echo "Invalid selection. Please choose 'aws' or 'gcp'."
    fi
  done
else
  PROVIDER="$1"
  if [[ "$PROVIDER" != "aws" && "$PROVIDER" != "gcp" ]]; then
    echo "❌ Error: Invalid provider. Please use 'aws' or 'gcp'."
    exit 1
  fi
fi

if [[ "$PROVIDER" == "aws" ]]; then
  CLI="aws"
elif [[ "$PROVIDER" == "gcp" ]]; then
  CLI="gcloud"
fi

echo "✅ Provider selected: $PROVIDER"

# --- Step 3: Install cloud CLI if not present ---
if ! have "$CLI"; then
  echo "Installing $CLI CLI..."
  if [[ "$PROVIDER" == "aws" ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
  elif [[ "$PROVIDER" == "gcp" ]]; then
    sudo apt-get update && sudo apt-get install google-cloud-sdk
  fi
  echo "✅ $CLI CLI installed."
else
  echo "✅ $CLI CLI is already installed."
fi

# --- Step 4: Prompt for instance details and create config file ---
if [[ -f "$CONFIG_FILE" ]]; then
  if ask_yes_no "Configuration file '$CONFIG_FILE' already exists. Overwrite? [y/N]"; then
    rm -f "$CONFIG_FILE"
  else
    echo "ℹ️  Keeping existing configuration file."
  fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Please enter your instance details to create the configuration file:"
  read -p "Instance ID: " INSTANCE_ID
  read -p "Zone: " ZONE
  
  if [[ "$PROVIDER" == "aws" ]]; then
    read -p "Path to PEM file (e.g., ~/.ssh/my-key.pem): " PEM_FILE
    echo "INSTANCE_ID=$INSTANCE_ID" > "$CONFIG_FILE"
    echo "ZONE=$ZONE" >> "$CONFIG_FILE"
    echo "PEM_FILE=$PEM_FILE" >> "$CONFIG_FILE"
  elif [[ "$PROVIDER" == "gcp" ]]; then
    echo "INSTANCE_ID=$INSTANCE_ID" > "$CONFIG_FILE"
    echo "ZONE=$ZONE" >> "$CONFIG_FILE"
  fi
  echo "✅ Configuration file '$CONFIG_FILE' created."
fi

# --- Step 5: Add aliases to shell RC file ---
echo "Adding aliases to $SHELL_RC..."
if ! grep -qF "$ALIAS_BLOCK_START" "$SHELL_RC" 2>/dev/null; then
  {
    echo "$ALIAS_BLOCK_START"
  
    echo "alias gcloud-start='$SCRIPT_DIR/gcloud-start.sh'"
    echo "alias gcloud-stop='$SCRIPT_DIR/gcloud-stop.sh'"
    echo "alias gcloud-scp-to='$SCRIPT_DIR/gcloud-scp-to.sh'"
    echo "alias gcloud-scp-from='$SCRIPT_DIR/gcloud-scp-from.sh'"

    echo "alias aws-start='$SCRIPT_DIR/aws-start.sh'"
    echo "alias aws-stop='$SCRIPT_DIR/aws-stop.sh'"
    echo "alias aws-scp-to='$SCRIPT_DIR/aws-scp-to.sh'"
    echo "alias aws-scp-from='$SCRIPT_DIR/aws-scp-from.sh'"
    echo "alias aws-stream='$SCRIPT_DIR/aws-stream.sh'"

    echo "$ALIAS_BLOCK_END"
  } >> "$SHELL_RC"

else
  echo "ℹ️  Aliases already present in $SHELL_RC."
fi

if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
  echo "⚠️ To activate aliases source $SHELL_RC"
else
  # Add aliases to current session for immediate use
  alias gcloud-start="$SCRIPT_DIR/gcloud-start.sh"
  alias gcloud-stop="$SCRIPT_DIR/gcloud-stop.sh"
  alias gcloud-scp-to="$SCRIPT_DIR/gcloud-scp-to.sh"
  alias gcloud-scp-from="$SCRIPT_DIR/gcloud-scp-from.sh"

  alias aws-start="$SCRIPT_DIR/aws-start.sh"
  alias aws-stop="$SCRIPT_DIR/aws-stop.sh"
  alias aws-scp-to="$SCRIPT_DIR/aws-scp-to.sh"
  alias aws-scp-from="$SCRIPT_DIR/aws-scp-from.sh"
  alias aws-stream="$SCRIPT_DIR/aws-stream.sh"

  echo "✅ Aliases added. They are now available in this session."
fi

echo "🎉 Setup complete!"