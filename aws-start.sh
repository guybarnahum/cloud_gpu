#!/usr/bin/env bash
set -e

# aws-start.sh: Starts an AWS EC2 instance.
# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

if [[ -f ".env" ]]; then 
  set -a            # Automatically export all variables
  source .env
  set +a            # Stop auto-exporting
fi

# --- Argument parsing ---
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_DEFAULT_REGION="${2:-$AWS_DEFAULT_REGION}"
AWS_EC2_PEM_FILE="${3:-$AWS_EC2_PEM_FILE}"

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_DEFAULT_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Missing required values." >&2
  echo "Usage: $0 <instance-id> <region> <path-to-pem-file>" >&2
  exit 1
fi

echo "Using Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "Using Region: ${AWS_DEFAULT_REGION}"

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

#
# This function displays a spinner while periodically running a check command
# until it succeeds or a timeout is reached.
#
# Usage: run_with_spinner "<description>" "<check_command>" <timeout_sec> <interval_sec>
#
run_with_spinner() {
  local description="$1"
  local check_command="$2"
  local timeout_seconds="$3"
  local check_interval_seconds="$4"

  echo "$description"

  local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  
  # Convert everything to milliseconds for integer math
  local interval_ms=200 
  local timeout_ms=$(( timeout_seconds * 1000 ))
  local check_every_ms=$(( check_interval_seconds * 1000 ))
  
  local elapsed_ms=0

  while [ $elapsed_ms -lt $timeout_ms ]; do
    # Only run the check command at the specified interval
    if (( elapsed_ms % check_every_ms == 0 )); then
      if eval "$check_command"; then
        printf "\n"
        return 0 
      fi
    fi

    # Animate spinner
    local spin_idx=$(( (elapsed_ms / interval_ms) % ${#spinner[@]} ))
    printf "   [%s] Working...\r" "${spinner[$spin_idx]}"
    
    sleep 0.2
    elapsed_ms=$(( elapsed_ms + interval_ms ))
  done

  printf "\n"
  echo "❌ Error: Timed out after $timeout_seconds seconds."
  return 1 
}

# --- Specific Wait Functions (now much simpler) ---

wait_for_instance_state() {
  local target_state="$1"
  local description="⏳ Waiting for instance to enter '$target_state' state..."
  # This command succeeds (exit code 0) only if grep finds the target state
  local check_cmd="aws ec2 describe-instances --instance-ids '$AWS_EC2_INSTANCE_ID' --region '$AWS_DEFAULT_REGION' --query 'Reservations[].Instances[].State.Name' --output text 2>/dev/null | grep -q '$target_state'"
  
  run_with_spinner "$description" "$check_cmd" 300 5
}

wait_for_ssh_ready() {
  local ip_address="$1"
  local description="⏳ Waiting for SSH service on $ip_address to become available..."
  # This command succeeds (exit code 0) only if nc can connect to port 22
  local check_cmd="nc -z -w 3 '$ip_address' 22 2>/dev/null"

  run_with_spinner "$description" "$check_cmd" 60 2
}

# --- Main script execution ---
echo "🚀 Starting instance $AWS_EC2_INSTANCE_ID in region $AWS_DEFAULT_REGION..."
aws ec2 start-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
echo "✅ Instance start request sent."

if ! wait_for_instance_state "running"; then
  echo "🛑 Stopping instance due to timeout..."
  aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
  exit 1
fi

echo "🔎 Retrieving public IP address..."
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$AWS_EC2_INSTANCE_ID" \
  --region "$AWS_DEFAULT_REGION" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ Error: Failed to retrieve public IP address. Check the instance's state." >&2
  exit 1
fi

echo "✅ Instance is running with public IP: $PUBLIC_IP"

if ! wait_for_ssh_ready "$PUBLIC_IP"; then
  echo "🛑 Stopping instance due to SSH timeout..."
  aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
  exit 1
fi

echo "✅ SSH service is ready."
echo "🔗 Connecting via SSH to ubuntu@$PUBLIC_IP..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$AWS_EC2_PEM_FILE" ubuntu@"$PUBLIC_IP"

