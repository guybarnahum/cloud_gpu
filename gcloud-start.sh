#!/usr/bin/env bash
set -e

# --- Get the directory of the script and change to it ---
# This ensures the script can find its related files, like .env
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

# gcloud-start.sh: Starts a GCE instance and connects via SSH.
#
# Usage: $0 [instance_id] [zone]
# Arguments will override values in the .gcloud_instance config file.

# --- Read config file (if it exists) ---
if [[ -f ".env" ]]; then
  source .env
fi

# --- Use arguments or fall back to config file ---
GCLOUD_INSTANCE_ID="${1:-$GCLOUD_INSTANCE_ID}"
GCLOUD_ZONE="${2:-$GCLOUD_ZONE}"

# --- Fail if values are not set ---
if [[ -z "$GCLOUD_INSTANCE_ID" || -z "$GCLOUD_ZONE" ]]; then
  echo "❌ Error: Instance id or zone not specified."
  echo "Please provide them as arguments or in a .env config file."
  echo "Usage: $0 <instance-id> <zone>"
  exit 1
fi

echo "🚀 Starting instance '$GCLOUD_INSTANCE_ID' in zone '$GCLOUD_ZONE'..."

# --- Start the instance ---
gcloud compute instances start "$GCLOUD_INSTANCE_ID" --zone="$GCLOUD_ZONE"

echo "✅ Instance '$GCLOUD_INSTANCE_ID' is now running."

# --- Connect via SSH ---
echo "Connecting via SSH..."
gcloud compute ssh "$GCLOUD_INSTANCE_ID" --zone="$GCLOUD_ZONE"
