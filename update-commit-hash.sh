#!/usr/bin/env bash

# Script to update COMMIT_HASH in proxy-manager.sh before commit

set -euo pipefail

SCRIPT_FILE="proxy-manager.sh"

if [ ! -f "$SCRIPT_FILE" ]; then
  echo "Error: $SCRIPT_FILE not found"
  exit 1
fi

# Get current commit hash (short, 7 chars)
if command -v git >/dev/null 2>&1; then
  COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "")
else
  COMMIT_HASH=""
fi

if [ -z "$COMMIT_HASH" ]; then
  echo "Warning: Could not get git commit hash. Using empty string."
  COMMIT_HASH=""
fi

# Update COMMIT_HASH in script
if grep -q "^COMMIT_HASH=" "$SCRIPT_FILE"; then
  # Update existing COMMIT_HASH
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    sed -i '' "s/^COMMIT_HASH=\".*\"/COMMIT_HASH=\"$COMMIT_HASH\"/" "$SCRIPT_FILE"
  else
    # Linux
    sed -i "s/^COMMIT_HASH=\".*\"/COMMIT_HASH=\"$COMMIT_HASH\"/" "$SCRIPT_FILE"
  fi
  echo "✅ Updated COMMIT_HASH to: $COMMIT_HASH"
else
  # Add COMMIT_HASH after VERSION line
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "/^VERSION=/a\\
COMMIT_HASH=\"$COMMIT_HASH\"
" "$SCRIPT_FILE"
  else
    sed -i "/^VERSION=/a COMMIT_HASH=\"$COMMIT_HASH\"" "$SCRIPT_FILE"
  fi
  echo "✅ Added COMMIT_HASH: $COMMIT_HASH"
fi

