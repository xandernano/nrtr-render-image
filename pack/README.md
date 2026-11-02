# GPU RENDER PACK — NRTR world engine on a rented GPU pod

Renders the four code-built 3D worlds (s1 bedroom / s2 heart / s10 map
room / s11 dawn) on a rented NVIDIA GPU instead of the Muse VM's 4 CPU
cores. Everything else — the audits, the gates, the compositing — is
unchanged. Only where the frames get computed moves.

**The one command** (run on the pod, from this pack's folder):

```bash
./run.sh            # setup + benchmark + render all four scenes
```

Variants: `./run.sh s1 s10` renders a subset ·
`BENCH_ONLY=1 ./run.sh` gets the cost number and renders nothing ·
`SKIP_BENCH=1 ./run.sh` skips the benchmark ·
`RATE_PER_HR=0.34 ./run.sh` prices the extrapolation at Community rates.

> **PATH ASSUMPTION — read this first.** `build_worlds.py` hardcodes
> `ROOT = os.path.expanduser('~/workspace/video-creation')` and writes
> all output to `ROOT/build/world3d/`, no matter where the script itself
> sits or what directory you run it from. So on the pod, work as the
> user whose `$HOME` should hold `workspace/video-creation` (on most
> pods that is `root`, so `/root/workspace/video-creation`), and expect
> frames + `WORLD_AUDIT` reports in `~/workspace/video-creation/build/world3d/`.

## 1. Rent the pod (your account, your payment — 5 minutes)

- Provider: RunPod (any equivalent hourly GPU host works; the pack only
  needs Ubuntu + an NVIDIA card + SSH).
- GPU: **RTX 4090**. Our scenes are low-poly at 10 Cycles samples, so a
  4090 is already overkill in our favor; anything RTX-class works.
- Tier: **Community** (~$0.34/hr posted) is third-party hosts — cheapest.
  **Secure** (~$0.74/hr posted) is RunPod-vetted datacenter machines —
  pricier, more predictable. Prices move; check the live rate before
  you commit. Billing is per-second/hourly while the pod runs.
- Image: a standard Ubuntu PyTorch/CUDA template is fine (we install
  our own Blender; we just need the NVIDIA driver, which GPU templates
  include). Disk: 10 GB is plenty (Blender ~1 GB, frames are small).

## 2. Upload

Upload **both**:

1. This pack (anywhere, e.g. `~/gpu-render-pack/`).
2. The video-creation build tree to `~/workspace/video-creation/` —
   at minimum `build/blender/build_worlds.py`. Simplest is the whole
   `video-creation` folder.

```bash
rsync -av ~/workspace/video-creation/  root@<pod-host>:~/workspace/video-creation/
rsync -av ~/workspace/video-creation/gpu-render-pack/  root@<pod-host>:~/gpu-render-pack/
```

If you skip #2, the wrapper falls back to the pack's snapshot copy of
`build_worlds.py` (see `SNAPSHOT.md`) — outputs are unaffected, because
of the hardcoded ROOT above.

## 3. Setup

```bash
cd ~/gpu-render-pack && ./setup.sh
```

It checks `nvidia-smi` (and aborts if there is no NVIDIA GPU), installs
portable **Blender 4.2.3** from blender.org into
`~/blender-4.2.3-linux-x64/`, and prints the GPU name and Blender
version. Idempotent — re-run it freely.

## 4. Benchmark FIRST — never commit blind

```bash
BENCH_ONLY=1 ./run.sh
```

This renders 10 real frames of s2 through the full pipeline (audits
included), times them, and prints seconds/frame plus the extrapolated
cost of a full four-scene batch at 450 / 500 / 550 frames, priced at
`RATE_PER_HR` (default $0.74). The benchmark frames are kept and count
toward production — the full render skips frames already on disk, so
nothing is paid for twice.

Do the shorts math with your own frame counts:

```
seconds per short  =  frames in the short  ×  seconds/frame (from the benchmark)
shorts per hour    =  3600 / seconds per short
cost per short     =  seconds per short / 3600  ×  pod $/hr
```

(The Sample 01 proof's four scenes total roughly 450–550 frames. A full
60-second short at 30 fps has 1800 frames overall, but only the beats
set in 3D worlds go through Blender — count those, not the runtime.)

## 5. Full render

```bash
./run.sh                 # all four scenes
./run.sh s1 s2           # a subset
```

Per scene, `build_worlds.py` first runs its world audit (geometry,
camera, lighting) and only renders the animation if the audit passes —
same gate as at home. A failing scene is skipped with the reason printed
(pass `--force` through, e.g. `./run.sh s1 --force`, only if you mean
it). `--test` and `--audit` also pass through. Progress is the frame
count climbing in `~/workspace/video-creation/build/world3d/<scene>/`;
the full log lands in `render.log` next to this README. Interrupted?
Re-run the same command — existing frames are skipped, it resumes.

## 6. Verify the GPU is actually engaged

Three independent confirmations:

1. **Setup** printed your card via `nvidia-smi` (e.g. `NVIDIA GeForce
   RTX 4090`).
2. **The render log** opens with the wrapper's line:
   `[gpu] compute_device_type=OPTIX — devices: NVIDIA GeForce RTX 4090 (OPTIX)`.
   If no GPU exists, the wrapper exits with code 3 and a FATAL message —
   it refuses to render on CPU, so a silent slow render cannot happen.
3. **Live check** in a second shell while rendering:
   `watch -n2 nvidia-smi` — GPU utilization above 0% and GPU memory
   allocated. CPU-only rendering would show ~0% GPU across the board.

Sanity check on speed: if the benchmark's seconds/frame is not
dramatically better than the ~25 s/frame the VM's CPU manages on these
scenes, stop and check the three items above before paying for a batch.

## 7. Download the results

```bash
rsync -av root@<pod-host>:~/workspace/video-creation/build/world3d/  ~/workspace/video-creation/build/world3d/
```

That brings home every frame plus each scene's `WORLD_AUDIT.md` /
`audit.json`. Compositing and the frame audit then run at home exactly
as before.

## 8. STOP the pod — this is the step that stops the billing

The moment the download is verified, **terminate (not just pause) the
pod** in the provider console. A running pod bills whether or not it is
rendering. If you stored anything on a separate network volume, that
can bill on its own — keep it deliberately or delete it, but decide.

## Troubleshooting

- **`[gpu] FATAL: no GPU compute device found` (exit 3):** the instance
  has no usable NVIDIA GPU or driver. Re-check the instance type; do not
  work around it — CPU rendering on a pod is the worst of both worlds.
- **Blender won't start / missing libraries:** `setup.sh` already tries
  an apt install of the usual suspects (libgl1, libegl1, libxkbcommon0,
  libxrender1, libxext6, libsm6). Run it again and read its output.
- **Frames not where you expect:** you are not the user you think you
  are. `ROOT` is `~/workspace/video-creation` of the user running
  Blender — check `echo $HOME`.
- **A scene's animation is skipped:** its world audit failed. The
  failing checks are printed in the log and in that scene's
  `WORLD_AUDIT.md`. Fix at home in the canonical script, re-copy, re-run
  (or `--force`, knowingly).
- **Wrong Blender version:** the pack pins 4.2.3 because the world
  script targets its API and denoiser settings. Don't substitute
  another version without re-running the audits.
