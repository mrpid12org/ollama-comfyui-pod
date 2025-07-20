# --- STAGE 1: Build Open WebUI Frontend ---
FROM node:20 as webui-builder
WORKDIR /app
# --- FIX: Reverting to a known stable release to avoid build errors ---
[cite_start]RUN git clone --depth 1 --branch v0.5.5 https://github.com/open-webui/open-webui.git . [cite: 1]
# --- FIX: Added --legacy-peer-deps to resolve dependency conflicts ---
[cite_start]RUN npm install --legacy-peer-deps && npm cache clean --force [cite: 2]
# --- FIX: Explicitly install the missing 'lowlight' package for this version ---
RUN npm install lowlight
RUN NODE_OPTIONS="--max-old-space-size=6144" npm run build

# --- STAGE 2: Final Production Image ---
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV OLLAMA_MODELS=/workspace/models
ENV PIP_ROOT_USER_ACTION=ignore
# Set ComfyUI URL for Open WebUI integration
ENV COMFYUI_URL=http://127.0.0.1:8188

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    supervisor \
    iproute2 \
    # --- FIX: Added ffmpeg to support audio features in Open WebUI ---
    ffmpeg \
    python3.11 \
    python3.11-venv \
    python3-venv \
    libgomp1 \
    build-essential \
    python3.11-dev \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean \
    [cite_start]&& rm -rf /var/lib/apt/lists/* [cite: 3]

# Install Ollama
[cite_start]RUN curl -fsSL https://ollama.com/install.sh | sh [cite: 4]

# Copy Open WebUI
COPY --from=webui-builder /app/backend /app/backend
COPY --from=webui-builder /app/build /app/build
COPY --from=webui-builder /app/CHANGELOG.md /app/CHANGELOG.md

# Install Open WebUI Python dependencies
RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3 get-pip.py && \
    python3 -m pip install -r /app/backend/requirements.txt -U && \
    rm -rf /root/.cache/pip

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    python3 -m pip install -r requirements.txt

# Create the ComfyUI config file to make model storage persistent
RUN tee /opt/ComfyUI/extra_model_paths.yaml > /dev/null <<EOF
comfyui:
    base_path: /workspace/comfyui-models
EOF

# Copy config files and custom scripts
[cite_start]COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf [cite: 5]
COPY entrypoint.sh /entrypoint.sh
COPY pull_model.sh /pull_model.sh
COPY idle_shutdown.sh /idle_shutdown.sh
RUN chmod +x /entrypoint.sh /pull_model.sh /idle_shutdown.sh

# Expose ports for clarity
EXPOSE 8888 8080 8188

# Set the entrypoint to start all services
ENTRYPOINT ["/entrypoint.sh"]
