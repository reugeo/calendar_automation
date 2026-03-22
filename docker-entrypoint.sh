#!/bin/sh
# =============================================================
# Custom Docker Entrypoint for n8n
# =============================================================
# WHAT THIS DOES:
# 1. Starts n8n in the background
# 2. Waits for n8n to be fully ready (health check)
# 3. Imports all workflow JSON files from /home/node/.n8n/workflows/
#    (n8n skips duplicates automatically using workflow IDs in the DB)
# 4. Keeps n8n running in the foreground
#
# NOTE: No file-based import tracker needed anymore.
# Previously we tracked imports using marker files on disk, but that
# disk is gone (we now use Supabase Postgres). Instead, n8n handles
# deduplication itself — if a workflow ID already exists in the DB,
# it updates it rather than creating a duplicate.
# =============================================================

echo "============================================="
echo "  n8n Calendar Automation - Starting Up"
echo "============================================="

# --- Start n8n in the background ---
echo "[1/4] Starting n8n in the background..."
n8n start &
N8N_PID=$!

# --- Wait for n8n to be ready ---
echo "[2/4] Waiting for n8n to be ready..."
RETRIES=40
until wget -qO- http://localhost:5678/healthz > /dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -le 0 ]; then
    echo "  n8n did not become ready in time. Skipping import."
    echo "[4/4] n8n is running on port 5678"
    echo "============================================="
    wait $N8N_PID
    exit 0
  fi
  echo "  Waiting... (${RETRIES} attempts remaining)"
  sleep 3
done
echo "  n8n is ready!"

# Extra wait to make sure DB is fully settled before importing
sleep 5

# --- Import workflow JSON files ---
# n8n uses the workflow ID inside each JSON to detect duplicates.
# Safe to run every startup - no duplicates will be created.
WORKFLOW_DIR="/home/node/.n8n/workflows"

echo "[3/4] Importing workflows..."
if [ -d "$WORKFLOW_DIR" ] && ls "$WORKFLOW_DIR"/*.json > /dev/null 2>&1; then
  COUNT=0
  for workflow_file in "$WORKFLOW_DIR"/*.json; do
    echo "  Importing: $(basename "$workflow_file")"
    if n8n import:workflow --input="$workflow_file"; then
      COUNT=$((COUNT + 1))
    else
      echo "  Warning: failed to import $(basename "$workflow_file")"
    fi
  done
  echo "  Done! ($COUNT workflows imported/updated)"
else
  echo "  No workflow files found in $WORKFLOW_DIR"
fi

# --- Keep n8n running ---
echo "[4/4] n8n is running on port 5678"
echo "============================================="
wait $N8N_PID