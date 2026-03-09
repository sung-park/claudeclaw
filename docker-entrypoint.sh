#!/bin/bash
set -e

echo "=== ClaudeClaw Docker ==="

# Wait until Claude is authenticated
# Check by looking for credential files in ~/.claude/
while true; do
  if claude auth status 2>/dev/null | grep -qi "logged in"; then
    break
  fi
  # Fallback: check if credential files exist
  if [ -f "$HOME/.claude/.credentials.json" ] || [ -f "$HOME/.claude/credentials.json" ]; then
    break
  fi
  echo ""
  echo "Claude Code is not logged in."
  echo "Run this from another terminal:"
  echo ""
  echo "  docker exec -it $(hostname) claude login"
  echo ""
  echo "Retrying in 30 seconds..."
  sleep 30
done

echo "Claude Code authenticated. Starting daemon..."
exec bun run /app/src/index.ts "$@"
