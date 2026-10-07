#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

BINARY = os.environ.get("SPOTIFY_BINARY", str(Path.home() / ".local/share/spotify-launcher/install/usr/share/spotify/spotify"))
RESULTS = Path.home() / ".local/share/spotify-debloat/results.jsonl"
SETTLE_SECONDS = 40
SAMPLE_SECONDS = 60
CLOCK_TICKS = os.sysconf("SC_CLK_TCK")


def spotify_pids():
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            argv0 = Path(f"/proc/{entry}/cmdline").read_bytes().replace(b"\0", b" ").split(b" ", 1)[0].decode()
        except (OSError, UnicodeDecodeError):
            continue
        if argv0 == BINARY:
            pids.append(int(entry))
    return pids


def cpu_ticks(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])
    except (OSError, IndexError, ValueError):
        return None


def memory_kib(pid):
    values = {"Pss": 0, "Rss": 0}
    try:
        for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
            key = line.split(":", 1)[0]
            if key in values:
                values[key] = int(line.split()[1])
    except OSError:
        pass
    return values


def is_main_process(pid):
    try:
        return b"--type=" not in Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return False


def kill_spotify():
    subprocess.run(["dbus-send", "--session", "--dest=org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2.Quit"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 15
    while spotify_pids() and time.time() < deadline:
        time.sleep(0.25)
    for pid in spotify_pids():
        if not is_main_process(pid):
            continue
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 20
    while spotify_pids() and time.time() < deadline:
        time.sleep(0.2)
    for pid in spotify_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(2)


def spotify_window_mapped():
    output = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout
    try:
        clients = json.loads(output)
    except json.JSONDecodeError:
        return None
    for client in clients:
        if client.get("class", "").lower() == "spotify" and client.get("mapped"):
            return client
    return None


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: bench.py LABEL [--env KEY=VALUE]... [-- spotify flags...]")
    label = sys.argv[1]
    arguments = sys.argv[2:]
    environment = dict(os.environ)
    flags = []
    index = 0
    while index < len(arguments):
        if arguments[index] == "--env":
            key, value = arguments[index + 1].split("=", 1)
            environment[key] = value
            index += 2
        elif arguments[index] == "--":
            flags = arguments[index + 1:]
            break
        else:
            flags.append(arguments[index])
            index += 1

    kill_spotify()
    started = time.monotonic()
    subprocess.Popen([BINARY, *flags], env=environment, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    startup_seconds = None
    window = None
    while time.monotonic() - started < 90:
        window = spotify_window_mapped()
        if window:
            startup_seconds = round(time.monotonic() - started, 2)
            break
        time.sleep(0.1)

    remaining = SETTLE_SECONDS - (time.monotonic() - started)
    if remaining > 0:
        time.sleep(remaining)
    startup_cpu_seconds = round(sum(cpu_ticks(pid) or 0 for pid in spotify_pids()) / CLOCK_TICKS, 2)

    gpu_monitor = subprocess.Popen(
        ["nvidia-smi", "pmon", "-s", "um", "-d", "1", "-c", str(SAMPLE_SECONDS - 2)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    start_ticks = {pid: cpu_ticks(pid) for pid in spotify_pids()}
    time.sleep(SAMPLE_SECONDS)
    end_pids = spotify_pids()
    used_ticks = 0
    for pid in end_pids:
        end = cpu_ticks(pid)
        if end is None:
            continue
        begin = start_ticks.get(pid)
        used_ticks += end - (begin if begin is not None else 0)
    pss_kib = sum(memory_kib(pid)["Pss"] for pid in end_pids)
    rss_kib = sum(memory_kib(pid)["Rss"] for pid in end_pids)

    gpu_output, _ = gpu_monitor.communicate()
    pid_set = set(end_pids)
    sm_samples = []
    framebuffer_mib = 0
    gpu_pids = set()
    for line in gpu_output.splitlines():
        if line.startswith("#"):
            continue
        columns = line.split()
        if len(columns) < 5 or not columns[1].isdigit() or int(columns[1]) not in pid_set:
            continue
        gpu_pids.add(int(columns[1]))
        sm_samples.append(0 if columns[3] == "-" else int(columns[3]))
        if len(columns) > 9 and columns[9].isdigit():
            framebuffer_mib = max(framebuffer_mib, int(columns[9]))

    result = {
        "label": label,
        "flags": flags,
        "env": {key: value for key, value in environment.items() if os.environ.get(key) != value},
        "startup_window_s": startup_seconds,
        "startup_cpu_s_first_40s": startup_cpu_seconds,
        "ozone": "xwayland" if window and window.get("xwayland") else "wayland",
        "processes": len(end_pids),
        "cpu_pct_one_core": round(used_ticks / CLOCK_TICKS / SAMPLE_SECONDS * 100, 2),
        "pss_mib": round(pss_kib / 1024, 1),
        "rss_mib": round(rss_kib / 1024, 1),
        "gpu_processes": len(gpu_pids),
        "gpu_sm_pct_avg": round(sum(sm_samples) / len(sm_samples), 2) if sm_samples else 0,
        "gpu_fb_mib": framebuffer_mib,
    }
    with RESULTS.open("a") as handle:
        handle.write(json.dumps(result) + "\n")
    print(json.dumps(result))
    if "--keep" not in os.environ.get("BENCH_OPTS", ""):
        kill_spotify()


if __name__ == "__main__":
    main()
