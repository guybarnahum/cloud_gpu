#!/usr/bin/env bash
set -e

# cloud_setup.sh: Sets up the cloud_gpu project for a chosen cloud provider.
# Optimized for macOS (MacBook Pro) and Linux.

# ------------- User-facing variables -------------
CONFIG_FILE=".env"
SHELL_RC=""
ALIAS_BLOCK_START="# >>> cloud_gpu aliases >>>"
ALIAS_BLOCK_END="# <<< cloud_gpu aliases <<<"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  zsh)  SHELL_RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bashrc" ;;
  *)    SHELL_RC="$HOME/.profile"; echo "⚠️ Unknown shell. Aliases will be added to $SHELL_RC" ;;
esac

# --- Step 2: Select cloud provider ---
if [[ -z "$1" ]]; then
  echo "Please choose a cloud provider (aws or gcp):"
  select provider in "aws" "gcp"; do
    if [[ -n "$provider" ]]; then
      PROVIDER="$provider"
      break
    fi
  done
else
  PROVIDER="$1"
fi

# --- Step 3: Install cloud CLI if not present (macOS/Linux detection) ---
OS_TYPE="$(uname)"
if [[ "$PROVIDER" == "aws" ]]; then
  CLI="aws"
  if ! have "aws"; then
    echo "📦 Installing AWS CLI..."
    if [[ "$OS_TYPE" == "Darwin" ]]; then
      # macOS Install
      curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
      sudo installer -pkg AWSCLIV2.pkg -target /
      rm AWSCLIV2.pkg
    else
      # Linux Install
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      unzip awscliv2.zip
      sudo ./aws/install
      rm -rf awscliv2.zip aws
    fi
  fi
elif [[ "$PROVIDER" == "gcp" ]]; then
  CLI="gcloud"
  if ! have "gcloud"; then
    echo "📦 Installing Google Cloud SDK..."
    if [[ "$OS_TYPE" == "Darwin" ]]; then
      echo "👉 Please install gcloud via Homebrew: brew install --cask google-cloud-sdk"
    else
      sudo apt-get update && sudo apt-get install google-cloud-sdk
    fi
  fi
fi

# --- Step 4: Create .env with correct variable names ---
if [[ -f "$CONFIG_FILE" ]]; then
  if ! ask_yes_no "Configuration file '$CONFIG_FILE' already exists. Overwrite? [y/N]"; then
    echo "ℹ️ Keeping existing configuration."
  else
    rm "$CONFIG_FILE"
  fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "--- ⚙️ Configuring $PROVIDER ---"
  if [[ "$PROVIDER" == "aws" ]]; then
    read -p "AWS Access Key ID: " AWS_KEY
    read -p "AWS Secret Access Key: " AWS_SECRET
    read -p "AWS Default Region (e.g., us-east-1): " AWS_REG
    read -p "EC2 Instance ID: " AWS_ID
    read -p "Path to PEM file: " AWS_PEM
    
    cat <<EOF > "$CONFIG_FILE"
AWS_ACCESS_KEY_ID=$AWS_KEY
AWS_SECRET_ACCESS_KEY=$AWS_SECRET
AWS_DEFAULT_REGION=$AWS_REG
AWS_EC2_INSTANCE_ID=$AWS_ID
AWS_EC2_PEM_FILE=$AWS_PEM
EOF
  else
    read -p "GCP Instance ID: " GCP_ID
    read -p "GCP Zone: " GCP_ZONE
    cat <<EOF > "$CONFIG_FILE"
GCLOUD_INSTANCE_ID=$GCP_ID
GCLOUD_ZONE=$GCP_ZONE
EOF
  fi
  echo "✅ Created $CONFIG_FILE"
fi

# --- Step 5: Add aliases to shell RC file ---
if ! grep -qF "$ALIAS_BLOCK_START" "$SHELL_RC" 2>/dev/null; then
  echo "Adding aliases to $SHELL_RC..."
  cat <<EOF >> "$SHELL_RC"

$ALIAS_BLOCK_START
alias gcloud-start='$SCRIPT_DIR/gcloud-start.sh'
alias gcloud-stop='$SCRIPT_DIR/gcloud-stop.sh'
alias gcloud-scp-to='$SCRIPT_DIR/gcloud-scp-to.sh'
alias gcloud-scp-from='$SCRIPT_DIR/gcloud-scp-from.sh'

alias aws-start='$SCRIPT_DIR/aws-start.sh'
alias aws-stop='$SCRIPT_DIR/aws-stop.sh'
alias aws-scp-to='$SCRIPT_DIR/aws-scp-to.sh'
alias aws-scp-from='$SCRIPT_DIR/aws-scp-from.sh'
alias aws-stream='$SCRIPT_DIR/aws-stream.sh'
$ALIAS_BLOCK_END
EOF
  echo "✅ Aliases added. Please run: source $SHELL_RC"
else
  echo "ℹ️ Aliases already exist in $SHELL_RC."
fi

echo "🎉 Setup complete!"