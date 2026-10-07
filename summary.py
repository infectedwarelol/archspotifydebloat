#!/usr/bin/env python3
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

RESULTS = Path.home() / ".local/share/spotify-debloat/results.jsonl"
METRICS = ["processes", "cpu_pct_one_core", "startup_cpu_s_first_40s", "pss_mib", "rss_mib",
           "startup_window_s", "gpu_processes", "gpu_sm_pct_avg", "gpu_fb_mib"]

runs = [json.loads(line) for line in RESULTS.read_text().splitlines() if line.strip()]
if "--raw" in sys.argv:
    for run in runs:
        print(run["label"].ljust(30), " ".join(f"{metric}={run.get(metric)}" for metric in METRICS), run["ozone"])
    sys.exit()

grouped = defaultdict(list)
for run in runs:
    if run["processes"] > 0:
        grouped[run["label"]].append(run)

print("variant".ljust(30), "n", *(metric[:12].rjust(13) for metric in METRICS))
for label, label_runs in grouped.items():
    medians = []
    for metric in METRICS:
        values = [run[metric] for run in label_runs if run.get(metric) is not None]
        medians.append(f"{statistics.median(values):.2f}" if values else "-")
    print(label.ljust(30), len(label_runs), *(value.rjust(13) for value in medians))
