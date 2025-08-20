#!/bin/bash
# SCRIPT V4.1 - Added 'set -e' to exit immediately on any error.
set -e

# --- 1. Configuration ---
URL_PART1="https://huggingface.co/lmstudio-community/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-MXFP4-00001-of-00002.gguf?download=true"
URL_PART2="https://huggingface.co/lmstudio-community/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-MXFP4-00002-of-00002.gguf?download=true"

FILENAME_PART1="gpt-oss-120b-MXFP4-00001-of-00002.gguf"
FILENAME_PART2="gpt-oss-120b-MXFP4-00002-of-00002.gguf"

FINAL_MODEL_NAME="gpt-oss-120b-MXFP4.gguf"

# --- Sanity Check: Exit if final model already exists ---
if [ -f "$FINAL_MODEL_NAME" ]; then
    echo "--- INFO: Final model '$FINAL_MODEL_NAME' already exists. Nothing to do. ---"
    exit 0
fi

# --- 2. Download Files with Aria2c (with resume capability) ---
echo "--- Starting Download ---"
echo "Downloading Part 1..."
aria2c -c -x 16 -s 16 -k 1M -o "$FILENAME_PART1" "$URL_PART1"

echo "Downloading Part 2..."
aria2c -c -x 16 -s 16 -k 1M -o "$FILENAME_PART2" "$URL_PART2"

# --- Verification ---
if [ ! -f "$FILENAME_PART1" ] || [ ! -f "$FILENAME_PART2" ]; then
    echo "--- ERROR: Download failed. One or both parts are missing. ---"
    exit 1
fi

echo "--- Download Complete ---"
echo "File sizes:"
ls -lh "$FILENAME_PART1" "$FILENAME_PART2"

# --- 3. Join Files Safely ---
echo "--- Pre-allocating space for the final model... ---"

# Calculate the exact total size
SIZE_PART1=$(stat -c %s "$FILENAME_PART1")
SIZE_PART2=$(stat -c %s "$FILENAME_PART2")
TOTAL_SIZE=$((SIZE_PART1 + SIZE_PART2))

# Create an empty file of the final size instantly
# If this fails due to lack of space, 'set -e' will stop the script here.
fallocate -l $TOTAL_SIZE "$FINAL_MODEL_NAME"

echo "--- Joining files with 'dd' (this is safe for low disk space)... ---"
# Copy part 1 to the beginning of the new file
dd if="$FILENAME_PART1" of="$FINAL_MODEL_NAME" bs=1M conv=notrunc

# Copy part 2, seeking past the bytes of part 1
dd if="$FILENAME_PART2" of="$FINAL_MODEL_NAME" bs=1M conv=notrunc seek=$(($SIZE_PART1 / 1048576))

echo "--- Join complete. ---"

# --- 4. Clean Up ---
echo "--- Cleaning up temporary part files... ---"
rm "$FILENAME_PART1" "$FILENAME_PART2"

# --- 5. Final Verification ---
echo "--- All Done! ---"
echo "Final model created: $FINAL_MODEL_NAME"
echo "Final file size:"
ls -lh "$FINAL_MODEL_NAME"
