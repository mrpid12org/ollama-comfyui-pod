# =================================================================
# Stage 1: The Builder
# =================================================================
# Use the full devel image with all build tools
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS builder

# --- THIS IS THE VERSION IDENTIFIER ---
RUN echo "--- DOCKERFILE VERSION: v23-Y-PROTOCOLS-FIX ---"

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
WORKDIR /app
RUN git clone --depth 1 --branch v0.6.18 https://github.com/open-webui/open-webui.git .
RUN apt-get update && apt-get install -y nodejs npm && \
    npm install -g n && \
    n 20 && \
    hash -r && \
    npm install --legacy-peer-deps && \
    npm install lowlight --legacy-peer-deps && \
    # --- THIS IS THE FIX ---
    npm install y-protocols --legacy-peer-deps && \
    NODE_OPTIONS="--max-old-space-size=6144" npm run build && \
    npm cache clean --force && \
    rm -rf /app/node_modules && \
    apt-get purge -y --auto-remove nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 3. Prepare Python Virtual Environment (Robust Method) ---
RUN python3 -m venv --without-pip /opt-venv
RUN curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
RUN /opt/venv/bin/python3 /tmp/get-pip.py
RUN rm /tmp/get-pip.py
ENV PATH="/opt/venv/bin:$PATH"

# --- 4. Install Python packages into the venv ---
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir wheel huggingface-hub PyYAML && \
    python3 -m pip install --pre --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121 && \
    python3 -m pip install --no-cache-dir -r /app/backend/requirements.txt -U

# --- 5. Install ComfyUI and its requirements ---
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    sed -i '/^torch/d' requirements.txt && \
    python3 -m pip install --no-cache-dir -r requirements.txt && \
    python3 -m pip install --no-cache-dir torchsde

# =================================================================
# Stage 2: The Final Production Image
# =================================================================
# Use the smaller 'base' image for a leaner final product
FROM nvidia/cuda:1
