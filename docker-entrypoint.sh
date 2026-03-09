#!/bin/bash
set -e

echo "=== ClaudeClaw Docker ==="

# Wait until Claude is authenticated
while ! claude --version > /dev/null 2>&1 || ! claude -p "ping" --output-format text > /dev/null 2>&1; do
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
