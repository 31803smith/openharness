#!/usr/bin/env bash
# Optional, minutes: MJX (MuJoCo on JAX), MuJoCo Playground (environments, PPO baselines for the
# Menagerie robots) and JAX for the CPU. On a Mac JAX runs on the CPU — fine for a smoke test, hours
# for a real policy; a GPU machine in Harness's Machines menu is where a run belongs.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. ./VERSIONS
# MJX releases with MuJoCo, version for version: pinned both, so the extras never move the MuJoCo
# setup.sh installed (an unpinned mujoco-mjx pulls the newest mujoco along with it).
.venv/bin/python -m pip install --quiet "jax" "mujoco==${MUJOCO}" "mujoco-mjx==${MUJOCO}" "playground"
.venv/bin/python -c 'import jax; from mujoco import mjx; import mujoco_playground; print("ok   jax", jax.__version__, "· mjx · playground", mujoco_playground.__version__, "· devices", jax.devices())'
