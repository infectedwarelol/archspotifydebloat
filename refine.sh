#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
best=(--ozone-platform=wayland --disable-smooth-scrolling
      --disable-features=Translate,OptimizationHints,AutofillServerCommunication
      --renderer-process-limit=1 --disable-background-networking --disk-cache-size=52428800
      --disable-gpu --in-process-gpu)
for i in $(seq "${RUNS:-3}"); do
  ./bench.py F-D+low-end-device-mode -- "${best[@]}" --enable-low-end-device-mode
  ./bench.py G-D+no-zygote -- "${best[@]}" --no-zygote
  ./bench.py H-D+low-end+no-zygote -- "${best[@]}" --enable-low-end-device-mode --no-zygote
done
