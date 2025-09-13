#!/usr/bin/env bash
set -e

# stream-client.sh: Streams a video from an EC2 instance to the local machine.
#
# This script uses an SSH master connection to create a robust tunnel, polls
# to ensure the tunnel is ready, and then starts the remote stream.
#
# Usage: $0 <remote-video-path> [instance-id] [region] [pem-file]

# --- Get the directory of the script to find .env and the server script ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# --- Read config file (if it exists) ---
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
fi

# --- Use arguments or fall back to config file ---
REMOTE_VIDEO_PATH="${1}"
AWS_EC2_INSTANCE_ID="${2:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_REGION="${3:-$AWS_EC2_REGION}"
AWS_EC2_PEM_FILE="${4:-$AWS_EC2_PEM_FILE}"

# --- Fail if values are not set ---
if [[ -z "$REMOTE_VIDEO_PATH" ]]; then
  echo "❌ Error: Missing the path to the video file on the remote instance."
  echo "Usage: $0 <remote-video-path> [instance-id] [region] [pem-file]"
  exit 1
fi

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Instance ID, region, or PEM file not specified."
  echo "Please provide them as arguments or in a .env config file."
  exit 1
fi

# --- Define a path for the SSH control socket ---
# This allows us to manage the background tunnel connection reliably.
CTRL_SOCK="/tmp/ssh-stream-tunnel-$(date +%s).sock"

# --- Define a cleanup function ---
# This will be called when the script exits to cleanly close the background tunnel.
cleanup() {
  echo "" # Newline for cleaner exit
  echo "🧹 Closing background SSH master connection..."
  if [[ -S "$CTRL_SOCK" ]]; then
    # Use the control socket to cleanly exit the background SSH process
    ssh -S "$CTRL_SOCK" -O exit "ubuntu@$PUBLIC_IP" 2>/dev/null || true
  fi
}

# --- Set the trap ---
# This ensures the cleanup function is called on script exit (Ctrl+C, etc.)
trap cleanup EXIT INT TERM

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

# --- Upload the server script ---
REMOTE_SCRIPT_PATH="/tmp/aws-stream-ec2.sh"
echo "🚀 Uploading aws-stream-ec2.sh to the instance at $REMOTE_SCRIPT_PATH..."
scp -i "$SCRIPT_DIR/$AWS_EC2_PEM_FILE" "$SCRIPT_DIR/aws-stream-ec2.sh" "ubuntu@$PUBLIC_IP:$REMOTE_SCRIPT_PATH" > /dev/null

echo "📺 Preparing to start stream and SSH tunnel..."

# --- 1. Start the SSH master connection and tunnel in the background ---
echo "🚇 Establishing background SSH connection..."
ssh -M -S "$CTRL_SOCK" -fnN \
    -o "ExitOnForwardFailure=yes" \
    -L 127.0.0.1:8080:localhost:8080 \
    -i "$SCRIPT_DIR/$AWS_EC2_PEM_FILE" \
    "ubuntu@$PUBLIC_IP"

# --- 2. Poll to wait for the tunnel to be ready ---
echo "⏳ Waiting for SSH tunnel to become active..."
POLL_TIMEOUT=10 # seconds
for (( i=0; i<$POLL_TIMEOUT; i++ )); do
  # Use netcat (nc) to check if the local port is open and listening
  if nc -z -w 1 127.0.0.1 8080; then
    echo "✅ Tunnel is active."
    break
  fi
  sleep 1
done

# Check if the loop timed out
if ! nc -z -w 1 127.0.0.1 8080; then
  echo "❌ Error: Timed out waiting for SSH tunnel."
  # The trap will fire here and clean up the master connection
  exit 1
fi

# --- 3. Launch the local video player ---
# We launch VLC *before* starting the blocking ffmpeg command.
echo "🎬 Launching VLC..."
case "$(uname -s)" in
  Linux*)    vlc tcp://127.0.0.1:8080 &> /dev/null & ;;
  Darwin*)   open -a VLC tcp://127.0.0.1:8080 ;;
esac

# Give VLC a moment to open before the stream starts hammering the port
sleep 2

# --- 4. Start the video stream on the remote server ---
# This re-uses the background connection and becomes the main blocking process.
# When you press Ctrl+C, this command will terminate, which will in turn
# stop the remote ffmpeg process. The trap will then clean up the background connection.
echo "▶️ Starting remote stream. Press CTRL+C in this window to stop."
ssh -S "$CTRL_SOCK" "ubuntu@$PUBLIC_IP" \
    "bash $REMOTE_SCRIPT_PATH \"$REMOTE_VIDEO_PATH\""
