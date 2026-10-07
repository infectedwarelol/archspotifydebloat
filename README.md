# ArchSpotifyDebloat

This is how I strip Spotify down to a lightweight music player on Arch Linux with Hyprland. I wanted something closer to Spotifast: no looping videos, no ads, no animations, and no idle CPU burn on a 4-thread i5-6500.

It patches the official client from `spotify-launcher` with SpotX-Bash and Spicetify. It also runs Spotify natively on Wayland with software rendering, so it stops waking up the NVIDIA card. Every change can be undone with one script.

## Results

I measured on an i5-6500 (4c/4t) with an RTX 3050, Hyprland 0.56, and Spotify 1.2.96.518, with the client idle and paused. The numbers are medians of 3 runs (2 for F and G). CPU is the sum over all Spotify processes, in percent of one core, sampled over 60 seconds. RAM is PSS, so shared memory between processes isn't counted twice.

| Setup | Processes | Idle CPU | CPU spent in first 40 s | RAM (PSS) | Uses the 3050 |
|---|---|---|---|---|---|
| Stock client, Xwayland | 9 | 14.7 % | 18.6 s | 898 MiB | yes |
| Patched, no flags | 9 | 4.78 % | 15.0 s | 848 MiB | yes |
| A: Wayland, GPU on | 9 | 0.40 % | 14.7 s | 907 MiB | yes |
| B: Wayland, `--disable-gpu` | 9 | 0.32 % | 12.7 s | 851 MiB | no |
| D: B + `--in-process-gpu` | 8 | 0.35 % | 12.7 s | 848 MiB | no |
| E: A + `--in-process-gpu` | 8 | 0.38 % | 14.7 s | 877 MiB | yes |
| **F: D + `--enable-low-end-device-mode`** | **8** | **0.31 %** | **13.7 s** | **828 MiB** | **no** |
| G: D + `--no-zygote` | 6 | 0.98 % | 12.9 s | 872 MiB | no |

F is what ships. B, D and F are basically tied on CPU, so F wins on memory and because it leaves the dGPU alone. The window shows up in under a second in every variant.

The raw numbers are in `results.jsonl`. `results-run1-corrupt-cache.jsonl` is a first pass that got thrown out (see the gotchas below).

## What gets changed

**Client patches** (`apply.sh`)
- SpotX-Bash runs with `-e -h -l -p`. That removes ads and sponsored stuff and patches out logging calls. It also skips the experimental flags (some of them turn video features on), hides non-music shelves on Home, and makes the lyrics background black.
- Spicetify runs on top with a CSS-only theme called `Lite`. It has no extensions, `expose_apis` is off, and Sentry and UI logging are disabled.

**Theme** (`config/spicetify/Themes/Lite/user.css`)
- Kills every CSS animation and transition, plus smooth scrolling, backdrop filters, blur, shadows, gradients and hover backgrounds.
- Hides all `<video>` elements, Canvas, music videos and the Now Playing extras (artist bio, tour dates, credits, merch).
- Hides Friend Activity and the upgrade buttons.

**Launch flags** (`config/spotify-launcher.conf`)
```
--ozone-platform=wayland --disable-smooth-scrolling
--disable-features=Translate,OptimizationHints,AutofillServerCommunication
--renderer-process-limit=1 --disable-background-networking --disk-cache-size=52428800
--disable-gpu --in-process-gpu --enable-low-end-device-mode
```

**Spotify prefs**
- Global `prefs`: `storage.size=1024`.
- `Users/<id>-user/prefs`: autoplay, crossfade, normalization, automix, desktop notifications and the auto-opening miniplayer are all off. Home page takeovers and promoted songs are hidden.

**Hyprland** (`config/hypr/spotify-lite.lua`)
- A window rule for Spotify only: no blur, no shadow, no animation, and it opens on workspace 9. Your global animation settings stay as they are.

**Staying patched**
- `spotify-lite` is a small wrapper the desktop entry points to. It launches with `--skip-update` so the client version stays pinned, and re-patches first if the client has changed underneath it.
- A systemd user path unit watches `~/.local/share/spotify-launcher/state.json`. If something else updates the client (say you ran plain `spotify-launcher`), the patches get reapplied and Spotify restarts.

## Requirements

- Arch Linux with `spotify-launcher` (the official repo package, not the AUR `spotify` one)
- Hyprland with the Lua config (0.56+)
- `perl`, `unzip`, `python3`, `curl`, `dbus` (for `dbus-send`)
- `zip` is optional. If it's missing, `bin/zip` stands in for it using Python's `zipfile` module.

## Install

The scripts expect the repo at `~/.local/share/spotify-debloat`. Run `spotify-launcher` once and log in before installing.

```bash
git clone https://gitlab.com/infectedware/archspotifydebloat.git ~/.local/share/spotify-debloat
~/.local/share/spotify-debloat/install.sh
```

`install.sh` does the following:
- checks the requirements and makes sure you've logged in
- closes Spotify cleanly
- backs up the client, `state.json`, `~/.config/spotify` and `hyprland.lua` into `backup-<date>/`
- installs Spicetify 2.45.3 to `~/.spicetify`
- copies the configs from `config/` into place
- adds the Hyprland rule
- writes the prefs
- patches the client
- enables the systemd path unit

It's safe to run again. The backup is only taken once, and it won't touch the Spicetify config or patch the client a second time.

It stops instead of overwriting a `~/.config/spotify-launcher.conf` or `spotify-launcher.desktop` that you made yourself, so move those out of the way first.

One step can't be scripted. In Spotify, go to Settings > Videos and Canvas and switch off Canvas, music videos and other videos. Those settings live on your account, not in a local file.

## Usage

- Start Spotify from your app menu as usual, or run `~/.local/share/spotify-debloat/spotify-lite`.
- To update Spotify on purpose: `spotify-lite --update`. It downloads the new client and patches it right away.
- After editing `user.css`: `./apply.sh css`
- Want the flags on the GPU instead? Edit `~/.config/spotify-launcher.conf`.

## Revert

```bash
~/.local/share/spotify-debloat/revert.sh
```

It asks once, then:
- stops Spotify
- restores the original client, `state.json` and `~/.config/spotify` from the backup
- removes the systemd units, launcher config, desktop override, Spicetify and the Hyprland rule
- reloads Hyprland

The backups stay where they are, so you can delete them yourself once you're happy.

## Benchmarking

```bash
./bench.py my-label -- --some-flag --another-flag
./variants.sh
python3 summary.py
python3 summary.py --raw
```

`bench.py` starts Spotify and waits 40 seconds for it to settle, then samples for 60 seconds. It sums CPU ticks and PSS across every Spotify process and reads per-process GPU usage from `nvidia-smi pmon`. Then it quits Spotify over MPRIS. `variants.sh` runs the main matrix and `refine.sh` runs the low-end and no-zygote variants. Set `SPOTIFY_BINARY` to benchmark a different client build.

## Gotchas I hit

- **`--disable-features=MediaRouter` crashes this CEF build** (Chromium 146) on startup, so it's not in the list.
- **Don't kill Spotify with `pkill`.** Killing every process at once corrupted `~/.cache/spotify` for me. After that the client hung on a blank shell at 100%+ CPU with a 4 to 5 GB renderer, even unpatched. Deleting the cache fixed it. SIGTERM on the main process doesn't quit it either. All the scripts here close it cleanly over MPRIS instead (`org.mpris.MediaPlayer2.Quit`).
- **Most playback prefs are per-user.** If you put them in the global `prefs` file, Spotify quietly drops them on the next save. They go in `Users/<id>-user/prefs`.
- **The patched client runs from an extracted folder.** Spicetify unpacks `Apps/xpui.spa` into `Apps/xpui/` and deletes the `.spa`. That's how `apply.sh` tells a patched client from a fresh one.
- **`spotify-launcher` has no config option to skip updates**, so the version pin only works through the wrapper and the desktop entry. The path unit covers the case where you start it some other way.

## Things that can't be fully turned off

- **Canvas and video settings** live on your Spotify account. The CSS hides every video, but the client may still download them unless you switch them off in Settings.
- **Social settings** (sharing what you listen to, new release notifications) are also stored on the account. Friend Activity is only hidden.
- **Offline sync** has no local switch. It just follows whichever playlists you've downloaded.
- **Some animations are JavaScript**, like the little equalizer bars on the playing track. CSS can't stop those, but they only run while music is playing.
- **The native client still sends some telemetry.** The UI-side logging is patched out where SpotX and Spicetify support it.
- **Intel iGPU offload** wasn't possible on my machine. The HD 530 is disabled in firmware and Hyprland runs on the 3050 anyway, so software rendering is the next best thing.

## Credits

- [SpotX-Bash](https://github.com/SpotX-Official/SpotX-Bash), MIT licensed. A pinned copy is in `spotx/`.
- [Spicetify](https://github.com/spicetify/cli)
