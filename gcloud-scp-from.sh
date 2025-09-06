#!/usr/bin/env bash
set -e

# gcloud-cp-from.sh: Copies a file from a GCE instance to the local machine.
#
# This script now operates relative to the directory it is invoked from.
#
# Usage: $0 <remote-path> <local-path> [instance-id] [zone]
# Arguments [instance-id] and [zone] will override values in the .env config file.

# --- Get the directory of the script to find .env ---
# This ensures the script can find its related files, like .env
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# --- Read config file (if it exists) ---
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
fi

# --- Use arguments or fall back to config file ---
REMOTE_PATH="${1}"
LOCAL_PATH="${2}"
GCLOUD_INSTANCE_ID="${3:-$GCLOUD_INSTANCE_ID}"
GCLOUD_ZONE="${4:-$GCLOUD_ZONE}"

# --- Fail if values are not set ---
if [[ -z "$REMOTE_PATH" || -z "$LOCAL_PATH" ]]; then
  echo "❌ Error: Missing required file paths."
  echo "Usage: $0 <remote-path> <local-path> [instance-id] [zone]"
  exit 1
fi

if [[ -z "$GCLOUD_INSTANCE_ID" || -z "$GCLOUD_ZONE" ]]; then
  echo "❌ Error: Instance id or zone not specified."
  echo "Please provide them as arguments or in a .env config file."
  echo "Usage: $0 <remote-path> <local-path> <instance-id> <zone>"
  exit 1
fi

echo "🚀 Copying '$GCLOUD_INSTANCE_ID:$REMOTE_PATH' to '$LOCAL_PATH' in zone '$GCLOUD_ZONE'..."

# --- Copy the file ---
gcloud compute scp --recurse "$GCLOUD_INSTANCE_ID":"$REMOTE_PATH" "$LOCAL_PATH" --zone="$GCLOUD_ZONE"
