#!/usr/bin/env bash
# GPU pod setup: verify the GPU, install portable Blender 4.2.3.
# Idempotent — safe to run repeatedly. Run on the POD, not on the Muse VM.
set -euo pipefail

BLENDER_VERSION="4.2.3"
BLENDER_TARBALL="blender-${BLENDER_VERSION}-linux-x64.tar.xz"
BLENDER_URL="https://download.blender.org/release/Blender4.2/${BLENDER_TARBALL}"
INSTALL_DIR="${HOME}/blender-${BLENDER_VERSION}-linux-x64"
BIN="${INSTALL_DIR}/blender"

echo "== GPU check =="
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found — this does not look like an NVIDIA GPU pod. Aborting." >&2
  exit 1
fi
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || nvidia-smi

if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q "Blender ${BLENDER_VERSION}"; then
  echo "== Blender ${BLENDER_VERSION} already installed: $BIN =="
else
  echo "== Downloading Blender ${BLENDER_VERSION} from blender.org =="
  TMP="$(mktemp -d)"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$BLENDER_URL" -o "$TMP/$BLENDER_TARBALL"
  elif command -v wget >/dev/null 2>&1; then
    wget "$BLENDER_URL" -O "$TMP/$BLENDER_TARBALL"
  else
    echo "ERROR: neither curl nor wget is available." >&2
    exit 1
  fi
  # The tarball extracts to blender-4.2.3-linux-x64/ under $HOME.
  tar -xJf "$TMP/$BLENDER_TARBALL" -C "$HOME"
  rm -rf "$TMP"
fi

if ! "$BIN" --version >/dev/null 2>&1; then
  echo "== Blender is missing system libraries; trying apt install =="
  if command -v apt-get >/dev/null 2>&1; then
    SUDO=""
    [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq libgl1 libegl1 libxkbcommon0 libxrender1 libxext6 libsm6 libxi6 libxxf86vm1 libxfixes3 >/dev/null
  fi
fi

"$BIN" --version
echo "SETUP OK — blender binary: $BIN"
