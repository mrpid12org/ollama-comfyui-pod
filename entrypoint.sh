#!/bin/bash
set -e

# --- Automatically clear old logs on every startup ---
echo "--- Clearing previous session logs... ---"
mkdir -p /workspace/logs
rm -f /workspace/logs/*

# --- Define persistent models directory ---
PERSISTENT_MODELS_DIR="/workspace/webui-data/user_data/models"

# --- Ensure download script exists in persistent storage ---
DOWNLOAD_SCRIPT_DEST="$PERSISTENT_MODELS_DIR/download_and_join.sh"
DOWNLOAD_SCRIPT_SRC="/usr/local/bin/download_and_join.sh"
if [ ! -f "$DOWNLOAD_SCRIPT_DEST" ]; then
    echo "--- Download script not found. Copying from image... ---"
    cp "$DOWNLOAD_SCRIPT_SRC" "$DOWNLOAD_SCRIPT_DEST"
fi

# --- WebUI persistent data fix ---
WEBUI_DATA_DIR="/app/backend/data"
PERSISTENT_WEBUI_DIR="/workspace/webui-data"
echo "--- Ensuring Open WebUI data is persistent... ---"
mkdir -p "$PERSISTENT_WEBUI_DIR"

if [ -d "$WEBUI_DATA_DIR" ] && [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "First run for WebUI detected. Migrating default data..."
  mv "$WEBUI_DATA_DIR"/* "$PERSISTENT_WEBUI_DIR/" 2>/dev/null || true
  rm -rf "$WEBUI_DATA_DIR"
fi

if [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "Linking $PERSISTENT_WEBUI_DIR to $WEBUI_DATA_DIR..."
  ln -s "$PERSISTENT_WEBUI_DIR" "$WEBUI_DATA_DIR"
fi
echo "--- WebUI data persistence configured. ---"

# --- Start all services via supervisor ---
SUPERVISOR_CONF="/etc/supervisor/conf.d/all-services.conf"
if [ ! -f "$SUPERVISOR_CONF" ]; then
    echo "--- FATAL ERROR: Supervisor configuration file not found at $SUPERVISOR_CONF ---"
    exit 1
fi

echo "--- Starting all services via supervisor... ---"
exec /usr/bin/supervisord -c "$SUPERVISOR_CONF"
