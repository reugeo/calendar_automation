#!/bin/sh
# =============================================================
# Custom Docker Entrypoint for n8n
# =============================================================
# WHAT THIS DOES:
# 1. Starts n8n in the background
# 2. Waits for n8n to be fully ready (health check)
# 3. Imports all workflow JSON files from /home/node/.n8n/workflows/
# 4. Keeps n8n running in the foreground
# =============================================================

set -e

echo "============================================="
echo "  n8n Calendar Automation - Starting Up"
echo "============================================="

# --- Start n8n in the background ---
# We start it in the background first so we can import workflows
# after the API is ready
echo "[1/4] Starting n8n in the background..."
n8n start &

# Save the process ID so we can bring it back to the foreground later
N8N_PID=$!

# --- Wait for n8n to be ready ---
# n8n needs a few seconds to initialize its database and API
echo "[2/4] Waiting for n8n to be ready..."
RETRIES=30
until wget -qO- http://localhost:5678/healthz > /dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -le 0 ]; then
    echo "  ⚠️  n8n did not become ready in time. Workflows may need manual import."
    break
  fi
  echo "  Waiting... (${RETRIES} attempts remaining)"
  sleep 2
done
echo "  ✅ n8n is ready!"

# --- Import workflow JSON files (smart: only imports NEW workflows) ---
# Tracks which files have already been imported using a marker directory.
# - Already imported workflows are SKIPPED (preserves credentials set in UI)
# - New workflow files are detected and imported automatically
IMPORT_TRACKER="/home/node/.n8n/.imported_workflows"
WORKFLOW_DIR="/home/node/.n8n/workflows"
mkdir -p "$IMPORT_TRACKER"

echo "[3/4] Checking for workflows to import..."
if [ -d "$WORKFLOW_DIR" ] && [ "$(ls -A $WORKFLOW_DIR/*.json 2>/dev/null)" ]; then
  NEW_COUNT=0
  SKIP_COUNT=0
  for workflow_file in "$WORKFLOW_DIR"/*.json; do
    filename=$(basename "$workflow_file")
    if [ -f "$IMPORT_TRACKER/$filename" ]; then
      echo "  ⏭️  Skipping (already imported): $filename"
      SKIP_COUNT=$((SKIP_COUNT + 1))
    else
      echo "  📂 Importing: $filename"
      if n8n import:workflow --input="$workflow_file"; then
        # Mark this file as imported
        touch "$IMPORT_TRACKER/$filename"
        NEW_COUNT=$((NEW_COUNT + 1))
      else
        echo "  ⚠️  Failed to import $filename"
      fi
    fi
  done
  echo "  ✅ Done! ($NEW_COUNT new, $SKIP_COUNT already imported)"
else
  echo "  ℹ️  No workflow files found in $WORKFLOW_DIR"
fi

# --- Keep n8n running in the foreground ---
# The 'wait' command makes this script wait for n8n to finish
# This keeps the Docker container running
echo "[4/4] n8n is running on port 5678"
echo "============================================="
wait $N8N_PID