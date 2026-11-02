# nrtr-render: ready-to-render Runpod image for the NRTR world engine.
#
# Base is the exact image our Pods already run, with Blender 4.2.3 and every
# system library it needs baked in, so a Pod boots render-ready and never
# pays the ~5 minute Blender install again (Xander's standing rule:
# never duplicate that startup waste).
#
# Published by GitHub Actions to:
#   ghcr.io/xandernano/nrtr-render:blender-4.2.3
#
# Deliberately NOT in this image: build_worlds.py. It changes with project
# state and uploads with the video-creation tree on each run.

FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

ARG BLENDER_VERSION=4.2.3
ARG BLENDER_TARBALL=blender-4.2.3-linux-x64.tar.xz
ARG BLENDER_URL=https://download.blender.org/release/Blender4.2/blender-4.2.3-linux-x64.tar.xz

# System libraries Blender needs. libxi6, libxxf86vm1 and libxfixes3 are
# included because the 2026-11-02 benchmark Pod proved Blender dies without
# them (libXi.so.6 missing) on exactly this base image.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      libgl1 libegl1 libxkbcommon0 libxrender1 libxext6 libsm6 \
      libxi6 libxxf86vm1 libxfixes3 \
      curl ca-certificates xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Portable Blender 4.2.3 (same official tarball the pack's setup.sh uses).
RUN curl -fL "${BLENDER_URL}" -o "/tmp/${BLENDER_TARBALL}" \
 && tar -xJf "/tmp/${BLENDER_TARBALL}" -C /opt \
 && rm -f "/tmp/${BLENDER_TARBALL}" \
 && ln -s /opt/blender-4.2.3-linux-x64 /root/blender-4.2.3-linux-x64

# Fail the build if any library Blender links against is unresolved.
RUN ldd /opt/blender-4.2.3-linux-x64/blender \
 && if ldd /opt/blender-4.2.3-linux-x64/blender | grep -q "not found"; then \
      echo "ERROR: unresolved Blender libraries above" >&2; exit 1; \
    fi

# Smoke test: Blender must run.
RUN /opt/blender-4.2.3-linux-x64/blender --version

# The render pack scripts (run.sh, setup.sh, render_gpu.py, README.md).
COPY pack/ /opt/gpu-render-pack/
RUN chmod +x /opt/gpu-render-pack/run.sh /opt/gpu-render-pack/setup.sh \
 && ln -s /opt/gpu-render-pack /root/gpu-render-pack

# run.sh defaults BLENDER_BIN to $HOME/blender-...; point it at the baked
# install so setup becomes a no-op check on Pods started from this image.
ENV BLENDER_BIN=/opt/blender-4.2.3-linux-x64/blender

LABEL org.opencontainers.image.title="nrtr-render" \
      org.opencontainers.image.description="Runpod render image: PyTorch base + Blender 4.2.3 + NRTR GPU render pack, boots render-ready" \
      org.opencontainers.image.source="https://github.com/xandernano/nrtr-render-image"
