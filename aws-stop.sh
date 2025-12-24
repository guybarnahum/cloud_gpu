#!/usr/bin/env bash
set -e

# aws-stop.sh: Stops a running AWS EC2 instance.
# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

if [[ -f ".env" ]]; then 
  set -a            # Automatically export all variables
  source .env
  set +a            # Stop auto-exporting
fi

# --- Argument parsing ---
# Using AWS_DEFAULT_REGION to match your working aws-start.sh
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_DEFAULT_REGION="${2:-$AWS_DEFAULT_REGION}"

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_DEFAULT_REGION" ]]; then
  echo "❌ Error: Missing required values." >&2
  echo "Usage: $0 <instance-id> <region>" >&2
  exit 1
fi

echo "Using Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "Using Region: ${AWS_DEFAULT_REGION}"

#
# This function displays a spinner while periodically running a check command
# until it succeeds or a timeout is reached.
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

# --- Specific Wait Function ---

wait_for_instance_state() {
  local target_state="$1"
  local description="⏳ Waiting for instance to enter '$target_state' state..."
  # This command succeeds (exit code 0) only if grep finds the target state
  local check_cmd="aws ec2 describe-instances --instance-ids '$AWS_EC2_INSTANCE_ID' --region '$AWS_DEFAULT_REGION' --query 'Reservations[].Instances[].State.Name' --output text 2>/dev/null | grep -q '$target_state'"
  
  run_with_spinner "$description" "$check_cmd" 300 5
}

# --- Main script execution ---
echo "🛑 Stopping instance $AWS_EC2_INSTANCE_ID in region $AWS_DEFAULT_REGION..."
aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
echo "✅ Instance stop request sent."

if wait_for_instance_state "stopped"; then
  echo "✅ Instance $AWS_EC2_INSTANCE_ID is now fully stopped."
else
  echo "⚠️  Warning: Script timed out, but the stop command was sent. Please check the AWS console."
  exit 1
fi