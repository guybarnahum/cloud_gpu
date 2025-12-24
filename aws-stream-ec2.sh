#!/usr/bin/env bash
set -e

# aws-stream-ec2.sh: Runs on the EC2 instance to stream a video file.
# --- Configuration ---
VIDEO_FILE="$1"
STREAM_PORT="${2:-8080}"  # Allow port override, default to 8080

# --- Validate input ---
if [[ -z "$VIDEO_FILE" ]]; then
  echo "❌ Error: No video file path provided." >&2
  exit 1
fi

if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "❌ Error: Video file not found at '$VIDEO_FILE' on the instance." >&2
  exit 1
fi

# --- Check for ffmpeg ---
if ! command -v ffmpeg &> /dev/null; then
  echo "❌ Error: ffmpeg is not installed on the server." >&2
  echo "👉 Fix: sudo apt-get update && sudo apt-get install -y ffmpeg" >&2
  exit 1
fi

# --- Cleanup old processes ---
# Using pkill/fuser to ensure the port is free for the new stream
echo "🧹 Ensuring port $STREAM_PORT is clear..." >&2
fuser -k -n tcp "$STREAM_PORT" 2>/dev/null || true
sleep 1

echo "🚀 Starting stream: $VIDEO_FILE" >&2
echo "📡 Listening on port: $STREAM_PORT" >&2
echo "💡 Note: This script will wait for a client (VLC) to connect before starting the read." >&2

# --- Start the ffmpeg stream ---
# -re: Read input at native frame rate (essential for real-time streaming)
# -stream_loop -1: Loop the video indefinitely
# -c:v libx264: Standard H.264 encoding for high compatibility
# -preset ultrafast: Minimal CPU usage (ideal for cloud instances)
# -tune zerolatency: Optimizes the encoder for streaming/low-delay
# -f mpegts: Use MPEG Transport Stream (standard for network streaming)
# ?listen=1: Tells ffmpeg to act as a server and wait for a connection
ffmpeg -re -stream_loop -1 -i "$VIDEO_FILE" \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 2M \
  -an -f mpegts "tcp://0.0.0.0:$STREAM_PORT?listen=1"