#!/bin/bash
set -e

# --- Automatically clear old logs on every startup ---
echo "--- Clearing previous session logs... ---"
mkdir -p /workspace/logs
rm -f /workspace/logs/*

# --- Ollama Model Directory Symlink ---
# Force Ollama to use the shared model directory on persistent storage.
OLLAMA_MODELS_DIR="/root/.ollama/models"
PERSISTENT_MODELS_DIR="/workspace/webui-data/user_data/models"

echo "--- Configuring Ollama to use persistent model storage... ---"
# Ensure the base directory for Ollama's config exists
mkdir -p /root/.ollama
# Ensure the target persistent models directory exists
mkdir -p "$PERSISTENT_MODELS_DIR"

# If the default models directory exists and is NOT a symlink, remove it.
if [ -d "$OLLAMA_MODELS_DIR" ] && [ ! -L "$OLLAMA_MODELS_DIR" ]; then
    echo "Removing default Ollama models directory to replace with symlink."
    rm -rf "$OLLAMA_MODELS_DIR"
fi

# Create the symlink if it doesn't already exist.
if [ ! -L "$OLLAMA_MODELS_DIR" ]; then
    echo "Linking $PERSISTENT_MODELS_DIR to $OLLAMA_MODELS_DIR..."
    ln -s "$PERSISTENT_MODELS_DIR" "$OLLAMA_MODELS_DIR"
fi
echo "--- Ollama model storage configured. ---"


# --- WebUI persistent data fix ---
WEBUI_DATA_DIR="/app/backend/data"
PERSISTENT_WEBUI_DIR="/workspace/webui-data"

echo "--- Ensuring Open WebUI data is persistent... ---"
mkdir -p "$PERSISTENT_WEBUI_DIR"

if [ -d "$WEBUI_DATA_DIR" ] && [ ! -L "$WEBUI_DATA_DIR" ]; then
  echo "First run for WebUI detected. Migrating default data..."
  # Move any existing files, ignore errors if the source is empty
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
