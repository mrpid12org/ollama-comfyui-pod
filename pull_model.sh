#!/bin/bash
# --- THIS IS A FIX ---
# Increased sleep to 30s to give the ollama server more time to initialize.
sleep 30

# This will download the high-performance Llama 3.1 70B model.
# The q4_k_m tag is optimized for a 48GB VRAM card.
MODEL_TO_PULL="mlabonne/llama-3.1-70b-instruct-lorablated-gguf:q4_k_m"

if ! ollama list | grep -q "$MODEL_TO_PULL"; then
  echo "--- Pulling default model: $MODEL_TO_PULL ---"
  ollama pull "$MODEL_TO_PULL"
else
  echo "--- Default model $MODEL_TO_PULL already exists ---"
fi
echo "--- Model check complete. ---"
