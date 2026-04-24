#!/usr/bin/env bash
set -e

# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Optional env-file override.
#
# Precedence:
#   1. --env /path/to/.env
#   2. AWS_ENV_FILE=/path/to/.env
#   3. $SCRIPT_DIR/.env
#
ENV_FILE="${AWS_ENV_FILE:-}"

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
  set -a            # Automatically export all variables
  source "$ENV_FILE"
  set +a            # Stop auto-exporting
else
  echo "No env file found at: $ENV_FILE"
fi

# --- Argument parsing ---
REMOTE_VIDEO_PATH="${1}"
AWS_EC2_INSTANCE_ID="${2:-$AWS_EC2_INSTANCE_ID}"
AWS_DEFAULT_REGION="${3:-$AWS_DEFAULT_REGION}"
AWS_EC2_PEM_FILE="${4:-$AWS_EC2_PEM_FILE}"

# --- Fail if values are not set ---
if [[ -z "$REMOTE_VIDEO_PATH" ]]; then
  echo "❌ Error: Missing the path to the video file on the remote instance." >&2
  echo "Usage: $0 <remote-video-path> [instance-id] [region] [pem-file]" >&2
  exit 1
fi

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_DEFAULT_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Missing required AWS values." >&2
  exit 1
fi

echo "Using Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "Using Region: ${AWS_DEFAULT_REGION}"

# --- Validate PEM file ---
if [[ ! -f "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: PEM file not found at $AWS_EC2_PEM_FILE." >&2
  exit 1
fi

# Permission Check
if [[ "$(uname)" == "Darwin" ]]; then
  PEM_PERMS=$(stat -f "%A" "$AWS_EC2_PEM_FILE")
else
  PEM_PERMS=$(stat -c "%a" "$AWS_EC2_PEM_FILE")
fi

if [[ "$PEM_PERMS" != "400" ]]; then
  echo "⚠️  Warning: PEM file permissions are not 400. Fixing..."
  chmod 400 "$AWS_EC2_PEM_FILE"
fi

# --- Define a path for the SSH control socket ---
CTRL_SOCK="/tmp/ssh-stream-tunnel-$(date +%s).sock"

# --- Cleanup function ---
cleanup() {
  echo ""
  echo "🧹 Closing background SSH master connection..."
  if [[ -S "$CTRL_SOCK" ]]; then
    ssh -S "$CTRL_SOCK" -O exit "ubuntu@$PUBLIC_IP" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "🔎 Retrieving public IP for $AWS_EC2_INSTANCE_ID..."
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_EC2_INSTANCE_ID" \
  --region "$AWS_DEFAULT_REGION" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
  echo "❌ Error: Failed to retrieve public IP. Is the instance running?" >&2
  exit 1
fi

echo "✅ Instance IP is $PUBLIC_IP"

# stream-client.sh: Streams a video from an EC2 instance to the local machine.
# --- Upload the server script ---
REMOTE_SCRIPT_PATH="/tmp/aws-stream-ec2.sh"
echo "🚀 Uploading streaming script to instance..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i "$AWS_EC2_PEM_FILE" "$SCRIPT_DIR/aws-stream-ec2.sh" "ubuntu@$PUBLIC_IP:$REMOTE_SCRIPT_PATH" > /dev/null

# --- 1. Start SSH tunnel in background ---
echo "🚇 Establishing SSH tunnel (Local 8080 -> Remote 8080)..."
ssh -M -S "$CTRL_SOCK" -fnN \
    -o "ExitOnForwardFailure=yes" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -L 127.0.0.1:8080:localhost:8080 \
    -i "$AWS_EC2_PEM_FILE" \
    "ubuntu@$PUBLIC_IP"

# --- 2. Poll for tunnel readiness (Using your millisecond logic) ---
echo "⏳ Waiting for tunnel..."
TUNNEL_READY=false
for (( i=0; i<50; i++ )); do # 50 * 0.2s = 10s timeout
  if nc -z -w 1 127.0.0.1 8080 2>/dev/null; then
    echo "✅ Tunnel is active."
    TUNNEL_READY=true
    break
  fi
  sleep 0.2
done

if [ "$TUNNEL_READY" = false ]; then
  echo "❌ Error: SSH tunnel failed to initialize."
  exit 1
fi

# --- 3. Launch VLC ---
echo "🎬 Launching VLC..."
case "$(uname)" in
  Darwin*) open -a VLC tcp://127.0.0.1:8080 ;;
  Linux*)  vlc tcp://127.0.0.1:8080 &> /dev/null & ;;
esac

sleep 2

# --- 4. Start Remote Stream ---
echo "▶️ Starting remote FFmpeg stream. Press CTRL+C to stop."
ssh -S "$CTRL_SOCK" "ubuntu@$PUBLIC_IP" "bash $REMOTE_SCRIPT_PATH \"$REMOTE_VIDEO_PATH\""