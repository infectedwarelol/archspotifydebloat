#!/usr/bin/env bash
set -euo pipefail

debloatDir="${HOME}/.local/share/spotify-debloat"
launcherDir="${HOME}/.local/share/spotify-launcher"
clientDir="${launcherDir}/install/usr/share/spotify"
backupDir=$(cat "${debloatDir}/backup-path")
hyprConfig="${HOME}/.config/hypr/hyprland.lua"

[[ -f "${backupDir}/spotify-launcher-install.tar" && -f "${backupDir}/config-spotify.tar" ]] || {
  echo "revert: backup missing in ${backupDir}" >&2
  exit 1
}

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

read -r -p "Restore Spotify, prefs and Hyprland rule from ${backupDir}? [y/N] " answer
[[ "${answer}" == [yY] ]] || exit 1

systemctl --user disable --now spotify-debloat.path 2>/dev/null || true
rm -f "${HOME}/.config/systemd/user/spotify-debloat.path" "${HOME}/.config/systemd/user/spotify-debloat.service"
systemctl --user daemon-reload

stopSpotify

rm -rf "${launcherDir}/install" "${launcherDir}/state.json"
tar -C "${launcherDir}" -xf "${backupDir}/spotify-launcher-install.tar"

rm -rf "${HOME}/.config/spotify"
tar -C "${HOME}/.config" -xf "${backupDir}/config-spotify.tar"

rm -f "${HOME}/.config/spotify-launcher.conf"
rm -f "${HOME}/.local/share/applications/spotify-launcher.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true

rm -rf "${HOME}/.spicetify" "${HOME}/.config/spicetify" "${HOME}/.local/state/spicetify"

if [[ -f "${hyprConfig}" ]] && grep -q 'name  = "spotify-lite"' "${hyprConfig}"; then
  python3 - "${hyprConfig}" <<'EOF'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
pattern = re.compile(r'\n*hl\.window_rule\(\{\n    name  = "spotify-lite",.*?\n\}\)\n', re.DOTALL)
path.write_text(pattern.sub("\n", text, count=1))
EOF
  hyprctl reload >/dev/null 2>&1 || true
fi

rm -f "${debloatDir}/patched.stamp"
echo "reverted. backups kept in ${backupDir}. delete ${debloatDir} when satisfied."
