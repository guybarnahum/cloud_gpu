#!/usr/bin/env bash
set -e

# aws-cp-from.sh: Copies a file or directory from an EC2 instance to the local machine.

# --- 1. Capture the directory where the user invoked the script ---
USER_INVOCATION_DIR="$(pwd)"

# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

if [[ -f ".env" ]]; then 
  set -a            # Automatically export all variables
  source .env
  set +a            # Stop auto-exporting
fi

# --- Argument parsing ---
REMOTE_PATH="${1}"
LOCAL_PATH="${2}"
AWS_EC2_INSTANCE_ID="${3:-$AWS_EC2_INSTANCE_ID}"
AWS_DEFAULT_REGION="${4:-$AWS_DEFAULT_REGION}"
AWS_EC2_PEM_FILE="${5:-$AWS_EC2_PEM_FILE}"

# --- Fail if file paths are not set ---
if [[ -z "$REMOTE_PATH" || -z "$LOCAL_PATH" ]]; then
  echo "❌ Error: Missing required file paths." >&2
  echo "Usage: $0 <remote-path> <local-path> [instance-id] [region] [pem-file]" >&2
  exit 1
fi

# --- 2. Fix LOCAL_PATH to be relative to the invocation directory ---
# If LOCAL_PATH does not start with a slash (it is relative)...
if [[ "$LOCAL_PATH" != /* ]]; then
  # ...prepend the user's invocation directory.
  LOCAL_PATH="$USER_INVOCATION_DIR/$LOCAL_PATH"
fi

# --- Fail if AWS values are not set ---
if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_DEFAULT_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Missing required AWS values." >&2
  echo "Usage: $0 <remote-path> <local-path> [instance-id] [region] [pem-file]" >&2
  exit 1
fi

echo "Using Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "Using Region: ${AWS_DEFAULT_REGION}"

# --- Validate PEM file ---
if [[ ! -f "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: PEM file not found at $AWS_EC2_PEM_FILE." >&2
  exit 1
fi

# Cross-platform check for file permissions (macOS & Linux)
PEM_PERMS=""
if [[ "$(uname)" == "Darwin" ]]; then
  PEM_PERMS=$(stat -f "%A" "$AWS_EC2_PEM_FILE")
else
  PEM_PERMS=$(stat -c "%a" "$AWS_EC2_PEM_FILE")
fi

if [[ "$PEM_PERMS" != "400" ]]; then
  echo "⚠️  Warning: PEM file permissions are not correct (should be 400, but are $PEM_PERMS)."
  echo "    To fix, run: chmod 400 \"$AWS_EC2_PEM_FILE\""
fi

echo "🔎 Retrieving public IP address for $AWS_EC2_INSTANCE_ID..."

# --- Get the public IP address ---
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_EC2_INSTANCE_ID" \
  --region "$AWS_DEFAULT_REGION" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
  echo "❌ Error: Failed to retrieve public IP address. Is the instance running?" >&2
  exit 1
fi

echo "✅ Instance IP is $PUBLIC_IP"
echo "🚀 Copying 'ubuntu@$PUBLIC_IP:$REMOTE_PATH' to '$LOCAL_PATH'..."

# --- Copy the file using scp ---
# -r allows for recursive directory copying
scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$AWS_EC2_PEM_FILE" "ubuntu@$PUBLIC_IP:$REMOTE_PATH" "$LOCAL_PATH"

echo "✅ Copy complete."