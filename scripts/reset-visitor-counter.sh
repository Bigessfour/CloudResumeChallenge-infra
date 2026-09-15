#!/usr/bin/env bash
# Reset the Cloud Resume Challenge visitor counter to a clean baseline.
#
# Requires AWS CLI v2 and credentials for Stephen's account (local profile or
# exported session — never commit keys). Uses DynamoDB UpdateItem so the
# counter item is created if missing.
#
# Usage:
#   ./scripts/reset-visitor-counter.sh
#   TABLE_NAME=cloudresume-visitor-counts AWS_REGION=us-east-1 ./scripts/reset-visitor-counter.sh
#   ./scripts/reset-visitor-counter.sh --hits 0
#
set -euo pipefail

TABLE_NAME="${TABLE_NAME:-cloudresume-visitor-counts}"
COUNTER_KEY="${COUNTER_KEY:-visitor-counter}"
AWS_REGION="${AWS_REGION:-us-east-1}"
HITS="0"

usage() {
  sed -n '2,12p' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage 0
      ;;
    --hits)
      HITS="${2:?--hits requires a non-negative integer}"
      shift 2
      ;;
    --table-name)
      TABLE_NAME="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage 1
      ;;
  esac
done

if ! [[ "$HITS" =~ ^[0-9]+$ ]]; then
  echo "hits must be a non-negative integer, got: $HITS" >&2
  exit 1
fi

echo "Resetting visitor counter in table '${TABLE_NAME}' (key '${COUNTER_KEY}') to hits=${HITS} in ${AWS_REGION}..."

aws dynamodb update-item \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME" \
  --key "{\"id\":{\"S\":\"${COUNTER_KEY}\"}}" \
  --update-expression "SET hits = :hits" \
  --expression-attribute-values "{\":hits\":{\"N\":\"${HITS}\"}}" \
  --return-values UPDATED_NEW

echo "Done. The next legitimate page load from https://stephenmckitrick.com will increment to $((HITS + 1))."
