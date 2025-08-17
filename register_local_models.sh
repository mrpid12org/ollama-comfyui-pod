#!/bin/bash
# SCRIPT V1.0 - Automatically find and register local GGUF models with Ollama.

# Give the Ollama server a moment to start up.
sleep 15

# This is the location where all your .gguf files are stored.
MODELS_DIR="/workspace/webui-data/user_data/models"

echo "--- Starting local model registration ---"
echo "Searching for GGUF models in: $MODELS_DIR"

if [ ! -d "$MODELS_DIR" ]; then
    echo "Warning: Models directory not found at $MODELS_DIR. Skipping registration."
    exit 0
fi

# Find all GGUF files and loop through them
find "$MODELS_DIR" -type f -name "*.gguf" | while read -r GGUF_FILE; do
    # Create a clean model name from the filename
    MODEL_NAME=$(basename "$GGUF_FILE" .gguf | sed 's/[^a-zA-Z0-9._-]//g')

    # Check if a model with this name already exists in Ollama
    if ollama list | grep -q "^${MODEL_NAME}:latest"; then
        echo "Model '$MODEL_NAME' already exists in Ollama. Skipping."
    else
        echo "Found new model: $GGUF_FILE"
        echo "Creating Modelfile for '$MODEL_NAME'..."

        # Define the content of the Modelfile
        MODELS_DIR_CONTENT="FROM $GGUF_FILE"

        # Create the model in Ollama using the Modelfile content
        echo "Registering '$MODEL_NAME' with Ollama..."
        ollama create "$MODEL_NAME" -f <(echo "$MODELS_DIR_CONTENT")
        echo "Successfully registered '$MODEL_NAME'."
    fi
done

echo "--- Model registration process complete. ---"
