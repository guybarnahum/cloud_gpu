#!/usr/bin/env bash
set -e

# aws-cp-to.sh: Copies a local file or directory to an EC2 instance.
#
# This script operates relative to the directory it is invoked from.
#
# Usage: $0 <local-path> <remote-path> [instance-id] [region] [pem-file]
# Arguments will override values in the .env config file.

# --- Get the directory of the script to find .env ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# --- Read config file (if it exists) ---
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
fi

# --- Use arguments or fall back to config file ---
LOCAL_PATH="${1}"
REMOTE_PATH="${2}"
AWS_EC2_INSTANCE_ID="${3:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_REGION="${4:-$AWS_EC2_REGION}"
AWS_EC2_PEM_FILE="${5:-$AWS_EC2_PEM_FILE}"

# --- Fail if values are not set ---
if [[ -z "$LOCAL_PATH" || -z "$REMOTE_PATH" ]]; then
  echo "❌ Error: Missing required file paths."
  echo "Usage: $0 <local-path> <remote-path> [instance-id] [region] [pem-file]"
  exit 1
fi

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Instance ID, region, or PEM file not specified."
  echo "Please provide them as arguments or in a .env config file."
  exit 1
fi

echo "🔎 Retrieving public IP for instance '$AWS_EC2_INSTANCE_ID'..."

# --- Get the public IP address ---
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_EC2_INSTANCE_ID" \
  --region "$AWS_EC2_REGION" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ Error: Failed to retrieve public IP address. Is the instance running?"
  exit 1
fi

echo "✅ Instance IP is $PUBLIC_IP"
echo "🚀 Copying local path '$LOCAL_PATH' to '$AWS_EC2_INSTANCE_ID:$REMOTE_PATH'..."

# --- Copy the file using scp ---
# -r allows for recursive directory copying
scp -r -i "$SCRIPT_DIR/$AWS_EC2_PEM_FILE" "$LOCAL_PATH" "ubuntu@$PUBLIC_IP:$REMOTE_PATH"

echo "✅ Copy complete."

