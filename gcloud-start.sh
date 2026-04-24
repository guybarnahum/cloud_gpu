#!/usr/bin/env bash
set -e

# --- Get the directory of the script and change to it ---
# This ensures the script can find its related files, like .env
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# gcloud-start.sh: Starts a GCE instance and connects via SSH.
#
# Usage: $0 [instance_id] [zone]
# Arguments will override values in the .gcloud_instance config file.

# Optional env-file override.
#
# Precedence:
#   1. --env /path/to/.env
#   2. GCLOUD_ENV_FILE=/path/to/.env
#   3. $PWD/.env
#   4. $SCRIPT_DIR/.env
#
ENV_FILE="${GCLOUD_ENV_FILE:-}"

if [[ "${1:-}" == "--env" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "❌ Error: --env requires a path to an env file." >&2
    exit 1
  fi
  ENV_FILE="$2"
  shift 2
fi

if [[ -z "$ENV_FILE" ]]; then
  if [[ -f "$PWD/.env" ]]; then
    ENV_FILE="$PWD/.env"
  else
    ENV_FILE="$SCRIPT_DIR/.env"
  fi
fi

if [[ -f "$ENV_FILE" ]]; then
  echo "Using env file: $ENV_FILE"
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "No env file found at: $ENV_FILE"
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

# --- Wait for the instance to be running ---
echo "✅ Instance start request sent. Waiting for the instance to become RUNNING..."

# --- Wait for the instance to be running with a timeout ---
TIMEOUT=60 # 10 minutes in seconds
start_time=$(date +%s)

while true; do
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))

  if [[ "$elapsed_time" -gt "$TIMEOUT" ]]; then
    echo "❌ Error: Timeout reached after $TIMEOUT seconds. Instance did not become RUNNING."
    exit 1
  fi

  STATUS=$(gcloud compute instances describe "$GCLOUD_INSTANCE_ID" --zone="$GCLOUD_ZONE" --format="value(status)")
  if [[ "$STATUS" == "RUNNING" ]]; then
    echo "✅ Instance '$GCLOUD_INSTANCE_ID' is now running."
    break
  fi
  echo "⏳ Current status: $STATUS. Waiting 10 seconds..."
  sleep 5
done

# --- Connect via SSH ---
sleep 5
echo "Connecting via SSH..."
gcloud compute ssh "$GCLOUD_INSTANCE_ID" --zone="$GCLOUD_ZONE"