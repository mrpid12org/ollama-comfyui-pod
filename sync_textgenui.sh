cat > /sync_textgenui.sh << 'EOL'
#!/bin/bash
# SCRIPT V1.2 - Uses curl to fetch model details for full compatibility.

# Give other services, especially Ollama, time to finish.
sleep 60

MODELS_DIR="/workspace/webui-data/user_data/models"
BLOBS_DIR="$MODELS_DIR/blobs"

echo "====================================================================="
echo "--- Starting TextgenUI Symlink Sync (v1.2) ---"
echo "====================================================================="

if ! command -v ollama &> /dev/null; then
    echo "[ERROR] Ollama command not found. Exiting."
    exit 1
fi

# Get a list of all model names from Ollama.
ollama list | awk '{print $1}' | tail -n +2 | while read -r MODEL_NAME_TAG; do
    echo
    echo "[INFO] Processing model: $MODEL_NAME_TAG"
    
    # Sanitize the model name for use as a filename (replace ':' with '-')
    SYMLINK_FILENAME=$(echo "$MODEL_NAME_TAG" | sed 's/:/-/g').gguf
    SYMLINK_PATH="$MODELS_DIR/$SYMLINK_FILENAME"

    if [ -L "$SYMLINK_PATH" ]; then
        if [ -e "$SYMLINK_PATH" ]; then
            echo "[SKIPPING] Valid symlink for '$SYMLINK_FILENAME' already exists."
            continue
        else
            echo "[CLEANUP] Removing broken symlink: $SYMLINK_FILENAME"
            rm "$SYMLINK_PATH"
        fi
    elif [ -f "$SYMLINK_PATH" ]; then
        echo "[WARNING] A real file exists at '$SYMLINK_PATH' and is not a symlink. Skipping."
        continue
    fi

    echo "       > Querying Ollama API for blob hash..."
    # Use curl to get the JSON data directly from the API
    JSON_OUTPUT=$(curl -s http://127.0.0.1:11434/api/show -d "{\"name\": \"$MODEL_NAME_TAG\"}")

    # Parse the JSON output to find the main data blob's hash
    BLOB_HASH=$(echo "$JSON_OUTPUT" | grep -A 1 '"mediaType": "application/vnd.ollama.image.model"' | tail -n 1 | grep -o 'sha256:[a-f0-9]*' | sed 's/sha256:/sha256-/g')

    if [ -z "$BLOB_HASH" ]; then
        echo "[ERROR] Could not determine blob hash for model '$MODEL_NAME_TAG'. Skipping."
        continue
    fi
    
    BLOB_FILE_PATH="$BLOBS_DIR/$BLOB_HASH"

    if [ -f "$BLOB_FILE_PATH" ]; then
        echo "       > Found blob file: $BLOB_HASH"
        echo "       > Creating symlink: $SYMLINK_FILENAME -> $BLOB_HASH"
        ln -s "$BLOB_FILE_PATH" "$SYMLINK_PATH"
    else
        echo "[ERROR] Blob file not found at '$BLOB_FILE_PATH'. Cannot create symlink."
    fi
done

echo
echo "--- TextgenUI Symlink Sync Complete ---"
EOL
