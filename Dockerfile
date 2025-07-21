# --- FINAL SINGLE-STAGE DOCKERFILE ---
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

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
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Build Open WebUI Frontend ---
WORKDIR /app
RUN git clone --depth 1 --branch v0.5.5 https://github.com/open-webui/open-webui.git .
RUN apt-get update && apt-get install -y nodejs npm && npm install -g n && n 20 && apt-get purge -y nodejs npm # Install Node.js
RUN npm install --legacy-peer-deps && npm cache clean --force
RUN npm install lowlight
RUN NODE_OPTIONS="--max-old-space-size=6144" npm run build

# Install Python dependencies
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir wheel huggingface-hub PyYAML && \
    python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U

# Install ComfyUI and its dependencies
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# --- UPDATED: Switched to a more explicit and robust YAML config format ---
# Create the ComfyUI config file to make model storage persistent
RUN tee /opt/ComfyUI/extra_model_paths.yaml > /dev/null <<EOF
checkpoints: /workspace/comfyui-models/checkpoints
unet: /workspace/comfyui-models/unet
vae: /workspace/comfyui-models/vae
clip: /workspace/comfyui-models/clip
loras: /workspace/comfyui-models/loras
t5: /workspace/comfyui-models/t5
controlnet: /workspace/comfyui-models/controlnet
embeddings: /workspace/comfyui-models/embeddings
hypernetworks: /workspace/comfyui-models/hypernetworks
EOF

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
RUN chmod +x /entrypoint.sh /pull_model.sh /idle_shutdown.sh

# Expose ports for clarity
EXPOSE 8888 8080 8188

# Set the entrypoint to start all services
ENTRYPOINT ["/entrypoint.sh"]
