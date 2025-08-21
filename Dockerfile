# =================================================================
# Stage 1: The Builder
# =================================================================
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

# --- THIS IS THE VERSION IDENTIFIER ---
RUN echo "--- DOCKERFILE VERSION: v38-SIMPLIFIED-BUILD ---"

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_ROOT_USER_ACTION=ignore

# --- 1. Install all build-time dependencies in one go ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    python3-pip \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Build Open WebUI Frontend ---
# NOTE: The version is pinned for build stability. To get the latest features,
# you can find the newest release tag at https://github.com/open-webui/open-webui/releases
# and update the `--branch` tag below. Removing `--branch` will pull the main branch, which might be unstable.
WORKDIR /app
RUN git clone --depth 1 --branch v0.6.18 https://github.com/open-webui/open-webui.git .
RUN apt-get update && apt-get install -y nodejs npm && \
    npm install -g n && \
    n 20 && \
    hash -r && \
    npm install --legacy-peer-deps && \
    npm install lowlight --legacy-peer-deps && \
    npm install y-protocols --legacy-peer-deps && \
    NODE_OPTIONS="--max-old-space-size=6144" npm run build && \
    npm cache clean --force && \
    rm -rf /app/node_modules && \
    apt-get purge -y --auto-remove nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 3. Prepare Python Virtual Environment ---
RUN python3 -m venv --without-pip /opt/venv
RUN curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
RUN /opt/venv/bin/python3 /tmp/get-pip.py
RUN rm /tmp/get-pip.py
ENV PATH="/opt/venv/bin:$PATH"

# --- 4. Install Python packages into the venv ---
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir wheel huggingface-hub PyYAML && \
    python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U

# --- 5. Install ComfyUI and its requirements ---
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    python3 -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt && \
    python3 -m pip install --no-cache-dir torchsde

# --- 6. Install ComfyUI Custom Nodes ---
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/was-node-suite-comfyui.git && \
    cd was-node-suite-comfyui && \
    python3 -m pip install -r requirements.txt

# =================================================================
# Stage 2: The Final Production Image
# =================================================================
FROM nvidia/cuda:12.8.1-base-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV OLLAMA_MODELS=/workspace/webui-data/user_data/models
ENV COMFYUI_URL="http://127.0.0.1:8188"
ENV PATH="/opt/venv/bin:$PATH"

# --- 1. Install RUNTIME-only dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    supervisor \
    ffmpeg \
    libgomp1 \
    python3.11 \
    nano \
    aria2 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Copy built assets from the 'builder' stage ---
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/backend /app/backend
COPY --from=builder /app/build /app/build
COPY --from=builder /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=builder /opt/ComfyUI /opt/ComfyUI

# --- 3. Create required directories ---
RUN mkdir -p /workspace/logs /workspace/webui-data/user_data/models

# --- 4. Install Ollama ---
RUN curl -fsSL https://ollama.com/install.sh | sh
RUN ollama --version

# --- 5. Copy local config files and scripts ---
COPY supervisord.conf /etc/supervisor/conf.d/all-services.conf
COPY entrypoint.sh /entrypoint.sh
COPY sync_textgenui.sh /sync_textgenui.sh
COPY idle_shutdown.sh /idle_shutdown.sh
COPY extra_model_paths.yaml /opt/ComfyUI/extra_model_paths.yaml
COPY download_and_join.sh /usr/local/bin/download_and_join.sh
RUN chmod +x /entrypoint.sh /sync_textgenui.sh /idle_shutdown.sh /usr/local/bin/download_and_join.sh

# --- 6. Expose ports and set entrypoint ---
EXPOSE 8888 8080 8188
ENTRYPOINT ["/entrypoint.sh"]
