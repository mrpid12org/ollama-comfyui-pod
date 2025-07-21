# =================================================================
# Stage 1: The Builder
# =================================================================
# Use the full devel image with all build tools
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore

# --- 1. Install Build-Time Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    python3-pip \
    build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. DIAGNOSTIC: Show initial disk space AND inode usage ---
RUN echo "--- BUILDER: Initial Disk and Inode Usage ---" && \
    echo "--- [h] Disk Space (Human-Readable) ---" && df -h && \
    echo "--- [i] Inode Usage ---" && df -i

# --- 3. Build Open WebUI Frontend ---
WORKDIR /app
RUN git clone --depth 1 --branch v0.5.5 https://github.com/open-webui/open-webui.git .
RUN apt-get update && apt-get install -y nodejs npm && \
    npm install -g n && \
    n 20 && \
    hash -r && \
    echo "--- BUILDER: Usage before 'npm install' ---" && df -hi && \
    npm install --legacy-peer-deps && \
    npm install lowlight && \
    echo "--- BUILDER: Usage AFTER 'npm install' (Peak Inodes) ---" && df -hi && \
    NODE_OPTIONS="--max-old-space-size=6144" npm run build && \
    npm cache clean --force && \
    rm -rf /app/node_modules && \
    echo "--- BUILDER: Usage after cleanup ---" && df -hi && \
    apt-get purge -y --auto-remove nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 4. Prepare Python Virtual Environment ---
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir wheel huggingface-hub PyYAML && \
    python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 && \
    python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U

RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    sed -i '/^torch/d' requirements.txt && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# --- 5. DIAGNOSTIC: Show disk space after Python setup ---
RUN echo "--- BUILDER: Final Usage ---" && df -hi


# =================================================================
# Stage 2: The Final Production Image
# =================================================================
# Use the smaller 'base' image for a leaner final product
FROM nvidia/cuda:12.8.1-base-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV OLLAMA_MODELS=/workspace/models
ENV COMFYUI_URL=http://127.0.0.1:8188
ENV PATH="/opt/venv/bin:$PATH"

# --- 1. Install RUNTIME-only dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    supervisor \
    ffmpeg \
    libgomp1 \
    python3.11 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy built assets from the 'builder' stage ---
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/backend /app/backend
COPY --from=builder /opt/ComfyUI /opt/ComfyUI

# --- 3. Create required directories ---
RUN mkdir -p /workspace/logs /workspace/models /workspace/webui-data && \
    mkdir -p /workspace/comfyui-models/checkpoints \
             /workspace/comfyui-models/unet \
             /workspace/comfyui-models/vae \
             /workspace/comfyui-models/clip \
             /workspace/comfyui-models/loras \
             /workspace/comfyui-models/t5 \
             /workspace/comfyui-models/controlnet \
             /workspace/comfyui-models/embeddings \
             /workspace/comfyui-models/hypernetworks

# --- 4. Install Ollama ---
RUN curl -fsSL https://ollama.com/install.sh | sh

# --- 5. Copy local config files and scripts ---
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY pull_model.sh /pull_model.sh
COPY idle_shutdown.sh /idle_shutdown.sh
COPY extra_model_paths.yaml /opt/ComfyUI/extra_model_paths.yaml
RUN chmod +x /entrypoint.sh /pull_model.sh /idle_shutdown.sh

# --- 6. Expose ports and set entrypoint ---
EXPOSE 8888 8080 8188
ENTRYPOINT ["/entrypoint.sh"]

# --- 7. DIAGNOSTIC: Show final disk and inode usage ---
RUN echo "--- FINAL IMAGE: Final Usage ---" && \
    echo "--- [h] Disk Space (Human-Readable) ---" && df -h && \
    echo "--- [i] Inode Usage ---" && df -i
