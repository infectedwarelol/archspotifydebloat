#!/usr/bin/env bash
set -euo pipefail

debloatDir="${HOME}/.local/share/spotify-debloat"
launcherDir="${HOME}/.local/share/spotify-launcher"
clientDir="${launcherDir}/install/usr/share/spotify"
spotifyConfigDir="${HOME}/.config/spotify"
hyprConfig="${HOME}/.config/hypr/hyprland.lua"
desktopFile="${HOME}/.local/share/applications/spotify-launcher.desktop"
launcherConfig="${HOME}/.config/spotify-launcher.conf"
spicetifyVersion="2.45.3"

fail() { echo "install: $*" >&2; exit 1; }

[[ "$(cd "$(dirname "$0")" && pwd)" == "${debloatDir}" ]] || fail "clone the repo to ${debloatDir} first"
for command in spotify-launcher perl unzip python3 curl tar dbus-send systemctl; do
  command -v "${command}" >/dev/null || fail "missing ${command}"
done
[[ -f "${launcherDir}/state.json" && -x "${clientDir}/spotify" ]] || fail "run spotify-launcher once first"
userPrefs=$(find "${spotifyConfigDir}/Users" -mindepth 2 -maxdepth 2 -path '*-user/prefs' -print -quit 2>/dev/null || true)
[[ -n "${userPrefs}" ]] || fail "log in to Spotify once first"

backupValid() {
  [[ -f "${debloatDir}/backup-path" ]] || return 1
  local backup
  backup=$(cat "${debloatDir}/backup-path")
  [[ -f "${backup}/spotify-launcher-install.tar" && -f "${backup}/config-spotify.tar" ]]
}

ownedByUs() { [[ ! -e "$1" ]] || grep -q -- "$2" "$1"; }
ownedByUs "${launcherConfig}" "--in-process-gpu" || fail "${launcherConfig} already exists, move it away first"
ownedByUs "${desktopFile}" "spotify-debloat" || fail "${desktopFile} already exists, move it away first"

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
stopSpotify

if backupValid; then
  echo "backup already exists: $(cat "${debloatDir}/backup-path")"
else
  [[ -d "${clientDir}/Apps/xpui" && ! -f "${clientDir}/Apps/xpui.spa" ]] && fail "client is already patched but no backup exists, reinstall it with spotify-launcher --force-update first"
  backup="${debloatDir}/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${backup}"
  chmod 700 "${backup}"
  tar -C "${launcherDir}" -cf "${backup}/spotify-launcher-install.tar" install state.json
  tar -C "${HOME}/.config" -cf "${backup}/config-spotify.tar" spotify
  [[ -f "${hyprConfig}" ]] && cp "${hyprConfig}" "${backup}/hyprland.lua"
  chmod 600 "${backup}"/*
  echo "${backup}" > "${debloatDir}/backup-path"
  echo "backup written: ${backup}"
fi

if [[ ! -x "${HOME}/.spicetify/spicetify" ]]; then
  mkdir -p "${HOME}/.spicetify"
  curl -fsSL "https://github.com/spicetify/cli/releases/download/v${spicetifyVersion}/spicetify-${spicetifyVersion}-linux-amd64.tar.gz" \
    | tar -xz -C "${HOME}/.spicetify"
fi

mkdir -p "${HOME}/.config/spicetify/Themes/Lite" "${HOME}/.config/systemd/user" "$(dirname "${desktopFile}")"
if [[ ! -f "${HOME}/.config/spicetify/config-xpui.ini" ]]; then
  sed -e "s|^prefs_path .*|prefs_path             = ${spotifyConfigDir}/prefs|" \
      -e '/^\[Backup\]/,$ s#^\(version\|with\)\( *\)=.*#\1\2= #' \
      "${debloatDir}/config/spicetify/config-xpui.ini" > "${HOME}/.config/spicetify/config-xpui.ini"
fi
cp "${debloatDir}/config/spicetify/Themes/Lite/user.css" "${HOME}/.config/spicetify/Themes/Lite/"
cp "${debloatDir}/config/spotify-launcher.conf" "${launcherConfig}"
cp "${debloatDir}/config/systemd/user/spotify-debloat.path" "${debloatDir}/config/systemd/user/spotify-debloat.service" \
   "${HOME}/.config/systemd/user/"
sed "s|^Exec=.*|Exec=${debloatDir}/spotify-lite %U|" "${debloatDir}/config/applications/spotify-launcher.desktop" > "${desktopFile}"
command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "${desktopFile}")" 2>/dev/null || true

if [[ -f "${hyprConfig}" ]]; then
  if ! grep -q 'name  = "spotify-lite"' "${hyprConfig}"; then
    { echo; cat "${debloatDir}/config/hypr/spotify-lite.lua"; } >> "${hyprConfig}"
    hyprctl reload >/dev/null 2>&1 || true
  fi
else
  echo "no ${hyprConfig}, skipped the Hyprland rule"
fi

python3 - "${spotifyConfigDir}/prefs" "${userPrefs}" <<'EOF'
import sys
from pathlib import Path


def set_prefs(path, wanted):
    lines = path.read_text().splitlines() if path.exists() else []
    kept = [line for line in lines if line.split("=", 1)[0] not in wanted]
    kept += [f"{key}={value}" for key, value in wanted.items()]
    path.write_text("\n".join(kept) + "\n")


set_prefs(Path(sys.argv[1]), {"storage.size": "1024"})
set_prefs(Path(sys.argv[2]), {
    "app.player.autoplay": "false",
    "audio.crossfade_v2": "false",
    "audio.normalize_v2": "false",
    "audio.automix": "false",
    "ui.track_os_notifications_enabled": "false",
    "ui.hide_hpto": "true",
    "ui.hide_promoted_songs": "true",
    "ui.miniplayer_auto_open_enabled": "false",
})
EOF

"${debloatDir}/apply.sh"

systemctl --user daemon-reload
systemctl --user enable --now spotify-debloat.path

echo "installed. turn off Canvas and videos in Spotify: Settings > Videos and Canvas."
