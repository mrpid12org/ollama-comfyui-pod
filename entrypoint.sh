#!/bin/bash
set -e

# --- ADDED: Automatically clear old logs on every startup ---
echo "--- Clearing previous session logs... ---"
mkdir -p /workspace/logs
rm -f /workspace/logs/*

# --- WebUI persistent data fix (from your original, more robust script) ---
WEBUI_DATA_DIR="/app/backend/data"
PERSISTENT_DATA_DIR="/workspace/webui-data"

echo "--- Ensuring Open WebUI data is persistent... ---"
mkdir -p "$PERSISTENT_DATA_DIR"

# This block is crucial for the first run to migrate any existing default data.
if [ -d "$WEBUI_DATA_DIR" ] && [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "First run detected. Migrating default data to persistent storage..."
  # Move any existing files, ignore errors if the source is empty
  mv "$WEBUI_DATA_DIR"/* "$PERSISTENT_DATA_DIR/" 2>/dev/null || true
  rm -rf "$WEBUI_DATA_DIR"
fi

# Create the symlink if it doesn't already exist.
if [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "Linking $PERSISTENT_DATA_DIR to $WEBUI_DATA_DIR..."
  ln -s "$PERSISTENT_DATA_DIR" "$WEBUI_DATA_DIR"
fi

echo "--- WebUI data persistence configured. ---"

# Define and check for the supervisor configuration file.
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi

# Start all services.
echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
