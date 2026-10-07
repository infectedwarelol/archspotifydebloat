#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
base=(--ozone-platform=wayland --disable-smooth-scrolling
      --disable-features=Translate,OptimizationHints,AutofillServerCommunication
      --renderer-process-limit=1 --disable-background-networking --disk-cache-size=52428800)
runs="${RUNS:-3}"
for i in $(seq "${runs}"); do
  SPOTIFY_BINARY="$PWD/stock-client/install/usr/share/spotify/spotify" ./bench.py stock-x11
  ./bench.py patched-x11-noflags
  ./bench.py A-wayland-gpu -- "${base[@]}"
  ./bench.py B-wayland-disable-gpu -- "${base[@]}" --disable-gpu
  ./bench.py D-wayland-disable-gpu-inproc -- "${base[@]}" --disable-gpu --in-process-gpu
  ./bench.py E-wayland-gpu-inproc -- "${base[@]}" --in-process-gpu
done
