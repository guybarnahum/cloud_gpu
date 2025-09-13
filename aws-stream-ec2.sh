#!/usr/bin/env bash
set -e

# aws-stream-ec2.sh: Runs on the EC2 instance to stream a video file.
# This script is intended to be called by the local stream-client.sh script.

VIDEO_FILE="$1"

# --- Validate input ---
if [[ -z "$VIDEO_FILE" ]]; then
  echo "❌ Error: No video file path provided."
  exit 1
fi
if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "❌ Error: Video file not found at '$VIDEO_FILE' on the instance."
  exit 1
fi

# --- Check for ffmpeg ---
if ! command -v ffmpeg &> /dev/null; then
  echo "❌ Error: ffmpeg is not installed on the server."
  echo "Please install it by running: sudo apt-get update && sudo apt-get install ffmpeg"
  exit 1
fi

STREAM_PORT=8080

# --- Automatically clean up any old streaming processes ---
echo "🧹 Cleaning up port $STREAM_PORT before starting..."
fuser -k -n tcp "$STREAM_PORT" 2>/dev/null || true
sleep 1

echo "✅ Server ready. Starting stream for '$VIDEO_FILE' (looping)..." >&2

# --- Start the ffmpeg stream ---
# -re: Read input at native frame rate (essential for streaming)
# -stream_loop -1: Loop the video indefinitely
# -i "$VIDEO_FILE": The input video file
# -c copy: Copy codecs without re-encoding (very low CPU usage)
# -f mpeg: Format as MPEG Program Stream, which is highly compatible with VLC.
# "tcp://localhost:$STREAM_PORT?listen=1": Listen for a connection on the specified port
# ffmpeg -re -stream_loop -1 -i "$VIDEO_FILE" -c copy -f mpeg "tcp://localhost:$STREAM_PORT?listen=1"

# --- Start the ffmpeg stream ---
# This command now RE-ENCODES the video for maximum compatibility.
# -c:v libx264: Use the standard H.264 video encoder.
# -preset ultrafast: Use minimal CPU, prioritizing speed over quality.
# -b:v 2M: Target a 2 Mbps video bitrate, easy to stream.
# -an: No audio.
# -f mpeg: Use the MPEG-PS container, which is very VLC-friendly.
ffmpeg -re -stream_loop -1 -i "$VIDEO_FILE" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -an -f mpeg "tcp://localhost:$STREAM_PORT?listen=1"