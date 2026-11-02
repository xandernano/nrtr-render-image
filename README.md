# nrtr-render-image

Builds the ready-to-render Runpod image for the NRTR world engine, so a Pod
boots render-ready and never pays the ~5 minute Blender install at startup
again.

**Image:** `ghcr.io/xandernano/nrtr-render:blender-4.2.3`

## What is in it

- Base: `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`, the same
  image our Pods already run.
- Blender 4.2.3 portable at `/opt/blender-4.2.3-linux-x64`, from the official
  blender.org tarball.
- Every system library Blender links against, including `libxi6`,
  `libxxf86vm1` and `libxfixes3`, which the 2026-11-02 benchmark Pod proved
  are required on this base. The build fails if `ldd` reports any library
  "not found", and a smoke test runs `blender --version`.
- The GPU render pack (`run.sh`, `setup.sh`, `render_gpu.py`, `README.md`)
  at `/opt/gpu-render-pack`, with `BLENDER_BIN` preset to the baked Blender
  so the pack's setup step becomes a no-op check.

Deliberately not in the image: `build_worlds.py`. It changes with project
state and uploads with the video-creation tree on each run.

## Rebuild

Push to `main` (or run the `build-render-image` workflow manually). GitHub
Actions builds and publishes to GHCR using the workflow's `GITHUB_TOKEN`
with `packages: write`. Bumping Blender means editing the version in the
`Dockerfile`, the tag in `.github/workflows/build.yml`, and these docs
together.

## Use

Create Runpod Pods with image `ghcr.io/xandernano/nrtr-render:blender-4.2.3`.
Upload the video-creation tree as usual, then run the pack from
`/opt/gpu-render-pack`.
