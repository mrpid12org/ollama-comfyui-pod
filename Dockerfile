# --- STAGE 1: Build Open WebUI Frontend ---
FROM node:20 as webui-builder
WORKDIR /app
RUN git clone --depth 1 --branch v0.5.5 https://github.com/open-webui/open-webui.git .
RUN npm install --legacy-peer-deps && npm cache clean --force
RUN npm install lowlight
RUN NODE_OPTIONS="--max-old-space-size=6144" npm run build


# --- STAGE 2: Build Python Dependencies ---
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 as python-builder
WORKDIR /build

# Install only build-time system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    python3.11 \
    python3.11-venv \
    build-essential \
    python3.11-dev \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create a virtual environment which will be copied to the final image
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements files needed for installation
COPY --from=webui-builder /app/backend/requirements.txt /tmp/webui_requirements.txt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /tmp/ComfyUI

# --- UPDATED: Split pip installs to resolve dependency conflicts ---
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir wheel huggingface-hub && \
    python3 -m pip install --no-cache-dir -r /tmp/webui_requirements.txt -U && \
    python3 -m pip install --no-cache-dir -r /tmp/ComfyUI/requirements.txt


# --- STAGE 3: Final Production Image ---
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV OLLAMA_MODELS=/workspace/models
ENV PIP_ROOT_USER_ACTION=ignore
ENV COMFYUI_URL=http://127.0.0.1:8188
# Add the Python virtual environment to the PATH
ENV PATH="/opt/venv/bin:$PATH"

# Install only RUNTIME system dependencies (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    supervisor \
    ffmpeg \
    libgomp1 \
    python3.11 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Copy the Python virtual environment from the python-builder stage
COPY --from=python-builder /opt/venv /opt/venv

# Copy applications from builder stages
COPY --from=webui-builder /app/backend /app/backend
COPY --from=webui-builder /app/build /app/build
COPY --from=webui-builder /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=python-builder /tmp/ComfyUI /opt/ComfyUI

# Create the ComfyUI config file to make model storage persistent
RUN tee /opt/ComfyUI/extra_model_paths.yaml > /dev/null <<EOF
base_path: /workspace/comfyui-models
EOF

# Create directories for all ComfyUI models
RUN mkdir -p /workspace/comfyui-models/checkpoints \
             /workspace/comfyui-models/unet \
             /workspace/comfyui-models/vae \
             /workspace/comfyui-models/clip \
             /workspace/comfyui-models/loras \
             /workspace/comfyui-models/t5

# Copy config files and custom scripts
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY pull_model.sh /pull_model.sh
COPY idle_shutdown.sh /idle_shutdown.sh
RUN chmod +x /entrypoint.sh /pull_model.sh /idle_shutdown.sh

# Expose ports for clarity
EXPOSE 8888 8080 8188

# Set the entrypoint to start all services
ENTRYPOINT ["/entrypoint.sh"]
