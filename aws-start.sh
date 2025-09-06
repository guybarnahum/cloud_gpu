#!/usr/bin/env bash
set -e

# --- Get the directory of the script and change to it ---
# This ensures the script can find its related files, like .env
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

# aws-start.sh: Starts an EC2 instance, waits for it to become ready, and then connects via SSH.
#
# Usage: $0 [aws_ec2_instance_id] [aws_zone] [pem_file]
# Arguments will override values in the .aws_instance config file.

# --- Read config file (if it exists) ---
if [[ -f ".env" ]]; then
  source .env
fi

# --- Use arguments or fall back to config file ---
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_ZONE="${2:-$AWS_EC2_ZONE}"
AWS_EC2_PEM_FILE="${3:-$AWS_EC2_PEM_FILE}"

# --- Fail if values are not set ---
if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_ZONE" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Missing required values."
  echo "Please provide them as arguments or in a .aws_instance config file."
  echo "Usage: $0 <instance-id> <zone> <path-to-pem-file>"
  exit 1
fi

# --- Validate PEM file permissions ---
if [[ ! -f "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: PEM file not found at $AWS_EC2_PEM_FILE."
  exit 1
fi
if [[ "$(stat -f %A "$AWS_EC2_PEM_FILE")" != "400" ]]; then
  echo "⚠️  Warning: PEM file permissions are not correct (should be 400)."
  echo "    Fix with: chmod 400 \"$AWS_EC2_PEM_FILE\""
fi

echo "🚀 Starting instance $AWS_EC2_INSTANCE_ID in zone $AWS_EC2_ZONE..."

# --- Start the instance ---
aws ec2 start-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --zone "$AWS_EC2_ZONE" > /dev/null
echo "✅ Instance start request sent."

# --- Wait for the instance to be running ---
echo "⏳ Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_ZONE"

# --- Get the public IP address ---
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_EC2_INSTANCE_ID" \
  --region "$AWS_EC2_ZONE" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ Error: Failed to retrieve public IP address. Check the instance's state."
  exit 1
fi

echo "✅ Instance is running with public IP: $PUBLIC_IP"

# --- Connect via SSH ---
echo "Connecting via SSH..."
ssh -i "$AWS_EC2_PEM_FILE" ec2-user@"$PUBLIC_IP"
