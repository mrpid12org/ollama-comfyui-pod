#!/bin/bash

# Ensure the log directory exists before supervisord starts.
mkdir -p /workspace/logs

# --- WebUI persistent data fix ---
WEBUI_DATA_DIR="/app/backend/data"
PERSISTENT_DATA_DIR="/workspace/webui-data"

echo "--- Ensuring Open WebUI data is persistent... ---"

mkdir -p "$PERSISTENT_DATA_DIR"

if [ -d "$WEBUI_DATA_DIR" ] && [ ! -L "$WEBUI_DATA_DIR" ]; then
  mv "$WEBUI_DATA_DIR"/* "$PERSISTENT_DATA_DIR/" 2>/dev/null || true
  rm -rf "$WEBUI_DATA_DIR"
fi

if [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "Linking $PERSISTENT_DATA_DIR to $WEBUI_DATA_DIR..."
  ln -s "$PERSISTENT_DATA_DIR" "$WEBUI_DATA_DIR"
fi

echo "--- WebUI data persistence configured. ---"

# Define the path to the supervisor configuration file
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"

# Check if the supervisor configuration file exists before trying to run it.
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi

# Start all services
echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
