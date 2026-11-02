#!/usr/bin/env python3
"""GPU wrapper for build_worlds.py — run INSIDE Blender on the rented pod:

    blender -b -P render_gpu.py -- [s1 s2 s10 s11 ...] [--test|--audit|--force]

What it does:
  1. Sets the Cycles compute device type to OPTIX (CUDA fallback, then
     ONEAPI / HIP / METAL), enables every non-CPU device, and prints the
     device names it found.
  2. Registers a persistent render_pre handler that sets
     scene.cycles.device = 'GPU' before every render, so the scenes
     build_worlds.py creates mid-run render on the GPU, not the CPU.
  3. Executes build_worlds.py UNCHANGED (runpy, run_name='__main__'), so
     its own argv parsing, audits, and output paths behave exactly as at
     home.

It FAILS LOUDLY (exit code 3) if no GPU compute device exists. It will
never silently fall back to CPU rendering — that is the whole point of
renting the pod.

Which build_worlds.py runs: $BUILD_WORLDS if set, else the canonical
~/workspace/video-creation/build/blender/build_worlds.py if present, else
the snapshot copy sitting next to this file.
"""
import os
import sys

import bpy
from bpy.app.handlers import persistent

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CANONICAL = os.path.expanduser(
    '~/workspace/video-creation/build/blender/build_worlds.py')
TARGET = (os.environ.get('BUILD_WORLDS')
          or (CANONICAL if os.path.exists(CANONICAL)
              else os.path.join(SCRIPT_DIR, 'build_worlds.py')))


def pick_gpu():
    prefs = bpy.context.preferences.addons['cycles'].preferences
    for ctype in ('OPTIX', 'CUDA', 'ONEAPI', 'HIP', 'METAL'):
        try:
            prefs.compute_device_type = ctype
            prefs.get_devices()
        except Exception as exc:  # backend unavailable on this build/host
            print(f'[gpu] {ctype} unavailable: {exc}', flush=True)
            continue
        gpus = [d for d in prefs.devices if d.type != 'CPU']
        if gpus:
            for d in prefs.devices:
                d.use = d.type != 'CPU'
            names = ', '.join(f'{d.name} ({d.type})' for d in gpus)
            print(f'[gpu] compute_device_type={ctype} — devices: {names}',
                  flush=True)
            return ctype, names
    print('[gpu] FATAL: no GPU compute device found on this machine. '
          'Refusing to fall back to CPU.', flush=True)
    raise SystemExit(3)


GPU_TYPE, GPU_NAMES = pick_gpu()


@persistent
def _force_gpu_device(*args):
    # Fires before every render job; build_worlds creates its scenes
    # after this wrapper loads, so the device is set per render, on the
    # scene actually being rendered.
    scene = bpy.context.scene
    if scene is not None and scene.render.engine == 'CYCLES':
        if scene.cycles.device != 'GPU':
            scene.cycles.device = 'GPU'
            print(f'[gpu] scene {scene.name!r} render device -> GPU '
                  f'({GPU_NAMES})', flush=True)


if _force_gpu_device not in bpy.app.handlers.render_pre:
    bpy.app.handlers.render_pre.append(_force_gpu_device)

_argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
print(f'[gpu] executing {TARGET} with args {_argv}', flush=True)

import runpy
runpy.run_path(TARGET, run_name='__main__')

print(f'[gpu] build_worlds finished — rendered on {GPU_NAMES} '
      f'via {GPU_TYPE}', flush=True)
