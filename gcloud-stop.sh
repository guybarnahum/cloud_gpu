#!/usr/bin/env bash
set -e

# --- Get the directory of the script and change to it ---
# This ensures the script can find its related files, like .env
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# gcloud-stop.sh: Stops a running GCE instance.
#
# Usage: $0 [instance_id] [zone]
# Arguments will override values in the .gcloud_instance config file.

# Optional env-file override.
#
# Precedence:
#   1. --env /path/to/.env
#   2. GCLOUD_ENV_FILE=/path/to/.env
#   3. $SCRIPT_DIR/.env
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
  ENV_FILE="$SCRIPT_DIR/.env"
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
  echo "❌ Error: Instance name or zone not specified."
  echo "Please provide them as arguments or in a .gcloud_instance config file."
  echo "Usage: $0 <instance-name> <zone>"
  exit 1
fi

echo "🛑 Stopping instance '$GCLOUD_INSTANCE_ID' in zone '$GCLOUD_ZONE'..."

# --- Stop the instance ---
gcloud compute instances stop "$GCLOUD_INSTANCE_ID" --zone="$GCLOUD_ZONE"

echo "✅ Instance '$GCLOUD_INSTANCE_ID' is now stopped."
