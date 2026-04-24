#!/usr/bin/env bash
set -e

# aws-start.sh: Starts an AWS EC2 instance with support for SSH arguments.
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

AWS_SSH_USER="${AWS_SSH_USER:-ubuntu}"

# --- SMART ARGUMENT PARSING ---
# Initialize with Env Vars (defaults)
_INSTANCE_ID="${AWS_EC2_INSTANCE_ID}"
_REGION="${AWS_DEFAULT_REGION}"
_PEM_FILE="${AWS_EC2_PEM_FILE}"
SSH_EXTRA_ARGS=()

# Counters to track which positional config args have been filled
_pos_count=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --) 
      # Explicit separator: Stop processing config, pass the rest to SSH
      shift
      SSH_EXTRA_ARGS+=("$@")
      break
      ;;
    -*)
      # Flag detected (e.g., -L, -v, -D): Assume the rest are SSH args
      # (Note: This assumes Instance IDs and Regions don't start with "-")
      SSH_EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      # Positional argument processing
      if [[ $_pos_count -eq 0 ]]; then
        _INSTANCE_ID="$1"
      elif [[ $_pos_count -eq 1 ]]; then
        _REGION="$1"
      elif [[ $_pos_count -eq 2 ]]; then
        _PEM_FILE="$1"
      else
        # If we have more than 3 positional args, pass them to SSH command (e.g. a command to run)
        SSH_EXTRA_ARGS+=("$1")
      fi
      ((_pos_count++))
      ;;
  esac
  shift
done

# Re-export to the variables the rest of the script uses
AWS_EC2_INSTANCE_ID="$_INSTANCE_ID"
AWS_DEFAULT_REGION="$_REGION"
AWS_EC2_PEM_FILE="$_PEM_FILE"

# --- Validation ---
if [[ -z "$AWS_EC2_INSTANCE_ID" || -z "$AWS_DEFAULT_REGION" || -z "$AWS_EC2_PEM_FILE" ]]; then
  echo "❌ Error: Missing required values." >&2
  echo "Usage: $0 [instance-id] [region] [pem-file] [SSH-FLAGS...]" >&2
  echo "   Or: $0 [SSH-FLAGS...] (if Env Vars are set)" >&2
  exit 1
fi

echo "Using Region: ${AWS_DEFAULT_REGION}"
if [[ ${#SSH_EXTRA_ARGS[@]} -gt 0 ]]; then
  echo "Passing Extra Args to SSH: ${SSH_EXTRA_ARGS[*]}"
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

aws_ec2_describe_instance_state() {
  aws ec2 describe-instances \
    --instance-ids "$AWS_EC2_INSTANCE_ID" \
    --region "$AWS_DEFAULT_REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
}

aws_ec2_describe_public_ip() {
  aws ec2 describe-instances \
    --instance-ids "$AWS_EC2_INSTANCE_ID" \
    --region "$AWS_DEFAULT_REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
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

# Spinner function:
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

# --- Check Functions ---
wait_for_instance_state() {
  local target_state="$1"
  local timeout_seconds=300
  local check_interval_seconds=5
  local elapsed_seconds=0

  echo "⏳ Waiting for instance to enter '$target_state' state..."

  while [[ $elapsed_seconds -lt $timeout_seconds ]]; do
    local state_output
    if ! state_output=$(aws_ec2_describe_instance_state 2>&1); then
      printf "\n"
      echo "❌ Error while checking instance state:" >&2
      echo "$state_output" >&2
      return 1
    fi

    printf "   Current state: %-20s\r" "$state_output"
    if [[ "$state_output" == "$target_state" ]]; then
      printf "\n"
      return 0
    fi

    sleep "$check_interval_seconds"
    elapsed_seconds=$((elapsed_seconds + check_interval_seconds))
  done

  printf "\n"
  echo "❌ Error: Timed out after $timeout_seconds seconds waiting for '$target_state'."
  return 1
}

wait_for_ssh_ready() {
  local ip_address="$1"
  local description="⏳ Waiting for SSH service on $ip_address to become available..."
  # This command succeeds (exit code 0) only if nc can connect to port 22
  local check_cmd="nc -z -w 3 '$ip_address' 22 2>/dev/null"
  run_with_spinner "$description" "$check_cmd" 60 2
}

# --- Main Execution ---
validate_aws_access

echo "🚀 Starting instance $AWS_EC2_INSTANCE_ID in region $AWS_DEFAULT_REGION..."
aws ec2 start-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
echo "✅ Instance start request sent."

if ! wait_for_instance_state "running"; then
  echo "🛑 Not continuing because the instance did not reach running state."
  aws ec2 stop-instances --instance-ids "$AWS_EC2_INSTANCE_ID" --region "$AWS_DEFAULT_REGION" > /dev/null
  exit 1
fi

echo "🔎 Retrieving public IP address..."
PUBLIC_IP=$(aws_ec2_describe_public_ip)

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
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
echo "🔗 Connecting via SSH to $AWS_SSH_USER@$PUBLIC_IP..."

# Execute SSH with the collected extra args
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$AWS_EC2_PEM_FILE" \
    "${SSH_EXTRA_ARGS[@]}" \
  "$AWS_SSH_USER"@"$PUBLIC_IP"