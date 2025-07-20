#!/bin/bash

# --- Configuration ---
# Read the timeout from an environment variable, with a default of 1800 seconds (30 minutes).
IDLE_TIMEOUT=${IDLE_TIMEOUT_SECONDS:-1800}

# How often (in seconds) to check for activity.
CHECK_INTERVAL=60

# The GPU utilization percentage that is considered "active".
GPU_UTILIZATION_THRESHOLD=10

echo "--- GPU Idle Shutdown Script Started (v7 - Logging) ---"
echo "Timeout is set to ${IDLE_TIMEOUT} seconds."
echo "Monitoring GPU utilization. Threshold for activity: ${GPU_UTILIZATION_THRESHOLD}%"

# --- Sanity Checks ---
if [ -z "$RUNPOD_POD_ID" ]; then
    echo "--- FATAL: RUNPOD_POD_ID environment variable not found."
    exit 0
fi
if ! command -v nvidia-smi &> /dev/null; then
    echo "--- FATAL: nvidia-smi command not found. Cannot monitor GPU."
    exit 0
fi
if ! command -v runpodctl &> /dev/null; then
    echo "--- FATAL: runpodctl command not found. Cannot self-terminate."
    exit 0
fi

# --- Main Loop ---
LAST_ACTIVE=$(date +%s)

while true; do
  # Get GPU utilization.
  UTIL_OUT=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | sort -nr | head -n1)

  # Log the current utilization at every check.
  echo "INFO: $(date): GPU Util read as: ${UTIL_OUT:-'N/A'}%."

  # Check if we got a valid number from nvidia-smi.
  if [[ "$UTIL_OUT" =~ ^[0-9]+$ ]]; then
    CURRENT_UTILIZATION=$UTIL_OUT
    
    if [ "$CURRENT_UTILIZATION" -gt "$GPU_UTILIZATION_THRESHOLD" ]; then
      LAST_ACTIVE=$(date +%s)
    else
      CURRENT_TIME=$(date +%s)
      IDLE_TIME=$((CURRENT_TIME - LAST_ACTIVE))

      if [ ${IDLE_TIME} -ge ${IDLE_TIMEOUT} ]; then
        echo "GPU has been idle for ${IDLE_TIME} seconds. Terminating pod ${RUNPOD_POD_ID} using runpodctl..."
        runpodctl remove pod $RUNPOD_POD_ID
        echo "Termination command sent. Script will now exit."
        exit 0
      fi
    fi
  else
    echo "Warning: Could not read GPU utilization. Output was: '${UTIL_OUT}'"
  fi
  
  sleep ${CHECK_INTERVAL}
done
