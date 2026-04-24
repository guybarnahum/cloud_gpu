#!/usr/bin/env bash
set -e

# aws-stop.sh: Stops a running AWS EC2 instance.
# --- Get script directory and load environment variables ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Optional env-file override.
#
# Precedence:
#   1. --env /path/to/.env
#   2. AWS_ENV_FILE=/path/to/.env
#   3. $PWD/.env
#   4. $SCRIPT_DIR/.env
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
  if [[ -f "$PWD/.env" ]]; then
    ENV_FILE="$PWD/.env"
  else
    ENV_FILE="$SCRIPT_DIR/.env"
  fi
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
# Using AWS_DEFAULT_REGION to match your working aws-start.sh
AWS_EC2_INSTANCE_ID="${1:-$AWS_EC2_INSTANCE_ID}"
AWS_DEFAULT_REGION="${2:-$AWS_DEFAULT_REGION}"

if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_DEFAULT_REGION" ]]; then
  echo "❌ Error: Missing required values." >&2
  echo "Usage: $0 <instance-id> <region>" >&2
  exit 1
fi

echo "Using Region: ${AWS_DEFAULT_REGION}"

aws_ec2_describe_instance_state() {
  aws ec2 describe-instances \
    --instance-ids "$AWS_EC2_INSTANCE_ID" \
    --region "$AWS_DEFAULT_REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
}

validate_aws_access() {
  echo "🔐 Validating AWS caller and EC2 describe permissions..."

  local identity
  if ! identity=$(aws sts get-caller-identity --output text 2>&1); then
    echo "❌ Error: Unable to read AWS caller identity." >&2
    echo "$identity" >&2
    exit 1
  fi

  local account arn
  account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)

  echo "Using AWS Account: ${account:-unknown}"
  echo "Using AWS Principal: ${arn:-unknown}"

  local describe_output
  if ! describe_output=$(aws_ec2_describe_instance_state 2>&1); then
    echo "❌ Error: Unable to describe instance $AWS_EC2_INSTANCE_ID in $AWS_DEFAULT_REGION." >&2
    echo "$describe_output" >&2

    if grep -q "UnauthorizedOperation" <<< "$describe_output"; then
      echo "" >&2
      echo "Missing permission: ec2:DescribeInstances" >&2
      echo "Ask the AWS account owner to allow ec2:DescribeInstances for this IAM user/role." >&2
    elif grep -q "InvalidInstanceID.NotFound" <<< "$describe_output"; then
      echo "" >&2
      echo "The instance was not found in this AWS account/region." >&2
      echo "Check AWS account, region, and instance ID." >&2
    fi

    exit 1
  fi

  echo "✅ Instance is visible. Current state: $describe_output"
}

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
      eval "$check_command"
      local check_rc=$?
      if [[ $check_rc -eq 0 ]]; then
        printf "\n"
        return 0 
      fi
      if [[ $check_rc -eq 2 ]]; then
        printf "\n"
        return 2
      fi
    fi

    # Animate spinner
    local spin_idx=$(( (elapsed_ms / interval_ms) % ${#spinner[@]} ))
    local spinner_text="${SPINNER_STATUS_LINE:-Working...}"
    printf "   [%s] %s\r" "${spinner[$spin_idx]}" "$spinner_text"
    
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
  local state_error=""
  local state_output=""

  check_instance_state_target() {
    if ! state_output=$(aws_ec2_describe_instance_state 2>&1); then
      state_error="$state_output"
      return 2
    fi

    SPINNER_STATUS_LINE="Current state: $state_output"
    [[ "$state_output" == "$target_state" ]]
  }

  SPINNER_STATUS_LINE="Current state: checking"
  run_with_spinner "⏳ Waiting for instance to enter '$target_state' state..." "check_instance_state_target" 300 5
  local wait_rc=$?
  SPINNER_STATUS_LINE=""

  if [[ $wait_rc -eq 2 ]]; then
    echo "❌ Error while checking instance state:" >&2
    echo "$state_error" >&2
    return 1
  fi

  return $wait_rc
}

# --- Main script execution ---
validate_aws_access

echo "🛑 Stopping instance $AWS_EC2_INSTANCE_ID in region $AWS_DEFAULT_REGION..."
aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
echo "✅ Instance stop request sent."

if wait_for_instance_state "stopped"; then
  echo "✅ Instance $AWS_EC2_INSTANCE_ID is now fully stopped."
else
  echo "⚠️  Warning: Script timed out, but the stop command was sent. Please check the AWS console."
  exit 1
fi