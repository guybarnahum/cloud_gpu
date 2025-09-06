#!/usr/bin/env bash
set -e

# --- Get the directory of the script and change to it ---
# This ensures the script can find its related files, like .env
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

# aws-stop.sh: Stops a running AWS EC2 instance.
#
# Usage: $0 [instance_id] [zone]
# Arguments will override values in the .aws_instance config file.

# --- Read config file (if it exists) ---
if [[ -f ".env" ]]; then
  source .env
fi

# --- Use arguments or fall back to config file ---
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_ZONE="${2:-$AWS_EC2_ZONE}"

# --- Fail if values are not set ---
if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_ZONE" ]]; then
  echo "❌ Error: Missing required values."
  echo "Please provide them as arguments or in a .aws_instance config file."
  echo "Usage: $0 <instance-id> <zone>"
  exit 1
fi

echo "🛑 Stopping instance '$AWS_EC2_INSTANCE_ID' in zone '$AWS_EC2_ZONE'..."

# --- Stop the instance ---
aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_ZONE" > /dev/null

echo "✅ Instance stop request sent."
echo "⏳ Waiting for instance to enter 'stopped' state..."

# --- Wait for the instance to stop completely ---
aws ec2 wait instance-stopped --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_ZONE"

echo "✅ Instance '$AWS_EC2_INSTANCE_ID' is now stopped."
