#!/usr/bin/env bash
set -euo pipefail

debloatDir="${HOME}/.local/share/spotify-debloat"
clientDir="${HOME}/.local/share/spotify-launcher/install/usr/share/spotify"
stateFile="${HOME}/.local/share/spotify-launcher/state.json"
stampFile="${debloatDir}/patched.stamp"
spicetify="${HOME}/.spicetify/spicetify"
lockFile="${XDG_RUNTIME_DIR:-/tmp}/spotify-debloat.lock"

exec 9>"${lockFile}"
flock 9

[[ -f "${stateFile}" && ( -f "${clientDir}/Apps/xpui.spa" || -d "${clientDir}/Apps/xpui" ) ]] || { echo "spotify-debloat: client not installed" >&2; exit 1; }

clientVersion=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "${stateFile}")
clientPatched() { [[ -f "${stampFile}" && "$(cat "${stampFile}")" == "${clientVersion}" && ! -f "${clientDir}/Apps/xpui.spa" && -f "${clientDir}/Apps/xpui/index.html" ]]; }
mode="${1:-auto}"

if [[ "${mode}" == "auto" ]] && clientPatched; then
  exit 0
fi

stopSpotify() {
  local pid
  dbus-send --session --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Quit 2>/dev/null || true
  for _ in $(seq 60); do pgrep -f "^${clientDir}/spotify" >/dev/null || return 0; sleep 0.25; done
  for pid in $(pgrep -f "^${clientDir}/spotify"); do
    grep -qa -- '--type=' "/proc/${pid}/cmdline" 2>/dev/null || kill "${pid}" 2>/dev/null || true
  done
  for _ in $(seq 100); do pgrep -f "^${clientDir}/spotify" >/dev/null || return 0; sleep 0.2; done
  pkill -9 -f "^${clientDir}/spotify" || true
}

wasRunning=''
if pgrep -f "^${clientDir}/spotify" >/dev/null; then
  wasRunning='true'
  stopSpotify
fi

if [[ "${mode}" == "css" ]]; then
  "${spicetify}" -q -n apply
else
  pathPrefix=''
  command -v zip >/dev/null || pathPrefix="${debloatDir}/bin:"
  "${spicetify}" -q -n clear || true
  PATH="${pathPrefix}${PATH}" bash "${debloatDir}/spotx/spotx.sh" -P "${clientDir}" -e -h -l -p -f --noninteractive --nocolor
  "${spicetify}" -q -n backup apply
fi

echo "${clientVersion}" > "${stampFile}"

if [[ "${wasRunning}" ]]; then
  setsid -f "${debloatDir}/spotify-lite" >/dev/null 2>&1
fi
