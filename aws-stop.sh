#!/usr/bin/env bash
set -e

# --- Get the directory of the script and change to it ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

# aws-stop.sh: Stops a running AWS EC2 instance.
#
# Usage: $0 [instance_id] [region]
# Arguments will override values in the .env config file.

# --- Read config file (if it exists) ---
if [[ -f ".env" ]]; then
  source .env
fi

# --- Use arguments or fall back to config file ---
# CORRECTED: Changed variable name to AWS_EC2_REGION
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_REGION="${2:-$AWS_EC2_REGION}"

# --- Fail if values are not set ---
if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_REGION" ]]; then
  echo "❌ Error: Missing required values."
  echo "Please provide them as arguments or in a .env config file."
  echo "Usage: $0 <instance-id> <region>"
  exit 1
fi

echo "🛑 Stopping instance '$AWS_EC2_INSTANCE_ID' in region '$AWS_EC2_REGION'..."

# --- Stop the instance ---
aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_REGION" > /dev/null

echo "✅ Instance stop request sent."
echo "⏳ Waiting for instance to enter 'stopped' state..."

# --- Wait for the instance to stop completely ---
aws ec2 wait instance-stopped --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_REGION"

echo "✅ Instance '$AWS_EC2_INSTANCE_ID' is now stopped."