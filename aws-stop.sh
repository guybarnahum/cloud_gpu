#!/usr/bin/env bash
set -e

# aws-stop.sh: Stops a running AWS EC2 instance.
#
# Usage: $0 [instance_id] [region]
# Arguments will override values in the .env config file.

# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
if [[ -f ".env" ]]; then source .env; fi

# --- Argument parsing ---
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_EC2_REGION="${2:-$AWS_EC2_REGION}"
if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_EC2_REGION" ]]; then
  echo "❌ Error: Missing required values." >&2
  echo "Usage: $0 <instance-id> <region>" >&2
  exit 1
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
  
  # FIX: Bash doesn't support floating point math. Pre-calculate iteration counts.
  # 300s timeout / 0.5s interval = 600 iterations
  # 5s check / 0.5s interval = check every 10 iterations
  local max_iterations=600
  local check_every_n_iterations=10
  
  local current_state="pending"

  for ((i=0; i<max_iterations; i++)); do
    # Only check the instance status every 5 seconds (10 iterations)
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
echo "🛑 Stopping instance '$AWS_EC2_INSTANCE_ID' in region '$AWS_EC2_REGION'..."
echo ""
echo "💡 Heads up: Gracefully stopping an instance can take 1-3 minutes to sync data."
echo "☕  This is the perfect time to grab a coffee! ☕"
echo ""

aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_EC2_REGION" > /dev/null
echo "✅ Instance stop request sent."

if wait_for_instance_state "stopped" "⏳ Waiting for instance to enter 'stopped' state..."; then
  echo "✅ Instance '$AWS_EC2_INSTANCE_ID' is now stopped."
else
  exit 1
fi