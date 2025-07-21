# --- FINAL SINGLE-STAGE DOCKERFILE ---
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV OLLAMA_MODELS=/workspace/models
ENV PIP_ROOT_USER_ACTION=ignore
ENV COMFYUI_URL=http://127.0.0.1:8188

# Install all system dependencies (build-time and runtime)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    supervisor \
    ffmpeg \
    libgomp1 \
    python3.11 \
    python3.11-dev \
    python3-pip \
    build-essential \
    sed \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Build Open WebUI Frontend ---
WORKDIR /app
RUN git clone --depth 1 --branch v0.5.5 https://github.com/open-webui/open-webui.git .
RUN apt-get update && apt-get install -y nodejs npm && npm install -g n && n 20 && apt-get purge -y nodejs npm # Install Node.js
RUN npm install --legacy-peer-deps && npm cache clean --force
RUN npm install lowlight
RUN NODE_OPTIONS="--max-old-space-size=6144" npm run build

# --- Install Python dependencies, forcing a compatible PyTorch version ---
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir wheel huggingface-hub PyYAML && \
    python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 && \
    python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U

# --- Install ComfyUI and its dependencies (UPDATED) ---
# This now removes torch from the requirements to prevent overwriting the CUDA version
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    sed -i '/^torch/d' requirements.txt && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# Create directories for all ComfyUI models
RUN mkdir -p /workspace/comfyui-models/checkpoints \
             /workspace/comfyui-models/unet \
             /workspace/comfyui-models/vae \
             /workspace/comfyui-models/clip \
             /workspace/comfyui-models/loras \
             /workspace/comfyui-models/t5 \
             /workspace/comfyui-models/controlnet \
             /workspace/comfyui-models/embeddings \
             /workspace/comfyui-models/hypernetworks

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Copy all local config files and scripts
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY pull_model.sh /pull_model.sh
COPY idle_shutdown.sh /idle_shutdown.sh
# --- UPDATED: Copy the new local config file instead of generating it ---
COPY extra_model_paths.yaml /opt/ComfyUI/extra_model_paths.yaml
RUN chmod +x /entrypoint.sh /pull_model.sh /idle_shutdown.sh

# Expose ports for clarity
EXPOSE 8888 8080 8188

# Set the entrypoint to start all services
ENTRYPOINT ["/entrypoint.sh"]
