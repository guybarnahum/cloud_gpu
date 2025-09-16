#!/usr/bin/env bash
set -e

# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
if [[ -f ".env" ]]; then source .env; fi

# --- Argument parsing ---
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_REGION="${2:-$AWS_EC2_REGION}"
AWS_EC2_PEM_FILE="${3:-$AWS_EC2_PEM_FILE}"

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Missing required values." >&2
  echo "Usage: $0 <instance-id> <region> <path-to-pem-file>" >&2
  exit 1
fi

# --- Validate PEM file ---
if [[ ! -f "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: PEM file not found at $AWS_EC2_PEM_FILE." >&2
  exit 1
fi

# Cross-platform check for file permissions (macOS & Linux)
PEM_PERMS=""
if [[ "$(uname)" == "Darwin" ]]; then
  PEM_PERMS=$(stat -f "%A" "$AWS_EC2_PEM_FILE")
else
  PEM_PERMS=$(stat -c "%a" "$AWS_EC2_PEM_FILE")
fi

if [[ "$PEM_PERMS" != "400" ]]; then
  echo "⚠️  Warning: PEM file permissions are not correct (should be 400, but are $PEM_PERMS)."
  echo "    To fix, run: chmod 400 \"$AWS_EC2_PEM_FILE\""
fi

# --- Reusable Polling Function ---
# Polls the state of an EC2 instance until it matches the target state or a timeout is reached.
wait_for_instance_state() {
  local target_state="$1"
  local description="$2"

  echo "$description"

  local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  local timeout_seconds=300
  local animation_interval=0.5 # Animate twice per second
  local check_interval_seconds=5 # Check status every 5 seconds
  
  # Bash doesn't support floating point math. Pre-calculate iteration counts.
  # 300s timeout / 0.5s interval = 600 iterations
  # 5s check / 0.5s interval = check every 10 iterations
  local max_iterations=600
  local check_every_n_iterations=10
  
  local current_state="pending"

  for ((i=0; i<max_iterations; i++)); do
    # Only check the instance status every 5 seconds
    if (( i % check_every_n_iterations == 0 )); then
      current_state=$(aws ec2 describe-instances \
        --instance-ids "$AWS_EC2_INSTANCE_ID" \
        --region "$AWS_EC2_REGION" \
        --query "Reservations[].Instances[].State.Name" \
        --output text 2>/dev/null || echo "querying")
    fi

    # Update the spinner on every iteration
    local spin_char=${spinner[i % ${#spinner[@]}]}
    printf "   [%s] Current state: %-15s\r" "$spin_char" "$current_state"
    
    if [[ "$current_state" == "$target_state" ]]; then
      printf "\n"
      return 0 # Success
    fi

    sleep "$animation_interval"
  done

  printf "\n"
  echo "❌ Error: Timed out after $timeout_seconds seconds. The instance is still in state: '$current_state'."
  return 1 # Failure
}
# --- End of Function ---


# --- Main script execution ---
echo "🚀 Starting instance $AWS_EC2_INSTANCE_ID in region $AWS_EC2_REGION..."
aws ec2 start-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_REGION" > /dev/null
echo "✅ Instance start request sent."

# Call the polling function to wait for the instance to be running
if ! wait_for_instance_state "running" "⏳ Waiting for instance to enter 'running' state..."; then
  # If it times out, stop the instance to prevent unnecessary charges
  echo "🛑 Stopping instance due to timeout..."
  aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_REGION" > /dev/null
  exit 1
fi

# --- Get the public IP address ---
echo "🔎 Retrieving public IP address..."
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_EC2_INSTANCE_ID" \
  --region "$AWS_EC2_REGION" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ Error: Failed to retrieve public IP address. Check the instance's state." >&2
  exit 1
fi

echo "✅ Instance is running with public IP: $PUBLIC_IP"

# --- Connect via SSH ---
echo "🔗 Connecting via SSH to ubuntu@$PUBLIC_IP..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$AWS_EC2_PEM_FILE" ubuntu@"$PUBLIC_IP"

