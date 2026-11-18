# macos-camilladsp-eq

Persistent, zero-polling system-wide Parametric EQ on macOS (`BlackHole 2ch` → `CamillaDSP` → USB DACs) with CoreAudio hot-plug autodetection, gapless level-matched A/B comparison, and an **Alfred 5** workflow.

## Supported Setups & Presets

| Location | USB DAC (CoreAudio Name) | Output Gear | Preset | Preamp / A/B Ref |
| :--- | :--- | :--- | :--- | :--- |
| **Work Desk** | `Schiit USB Audio Gen 2` (Jotunheim 1) | **Focal Clear Mg Pro** | `focal_clear_mg.yml` (Oratory1990 Harman 10-band) | `-11.2 dB` / `-7.5 dB` |
| **Work Desk** | `Schiit USB Audio Gen 2` (Jotunheim 1) | **ADAM Audio A3X** (13° stands) | `adam_a3x.yml` (UMIK-1 6-band nearfield room EQ) | `-6.5 dB` / `-7.5 dB` |
| **Couch** | `Speaker-Schiit USB Audio Device` (Modi 2) | **Audeze LCD-2 Classic** (Stock pads) | `lcd2c_stock.yml` (Oratory1990 Harman 10-band) | `-8.0 dB` / `-7.0 dB` |
| **Undocked / Office** | Any other output (Built-in, AirPods, HDMI) | Unchanged | `camilladsp` stopped (`0%` CPU); existing output preserved | — |

> **Multi-Mac / KVM Friendly:** Each MacBook runs its own event-driven CoreAudio listener (`camilladsp-watcher.swift` via `/usr/bin/swift`, `0.0%` idle CPU). Switching a USB dock/switch from your personal MacBook to your work MacBook automatically stops DSP + restores built-in speakers on the unplugged Mac and activates DSP + BlackHole routing on the newly plugged Mac within ~1 second.

---

## Quick Install (Work MacBook / Fresh Mac)

### Prerequisites
- **Xcode Command Line Tools** (`swift` & `python3`): `xcode-select --install`
- **Homebrew** (`brew`) — used by `install.sh` to install `blackhole-2ch` and `switchaudio-osx` if missing
- **Alfred 5** (with Powerpack) — optional, for the `eq` launcher workflow (open Alfred 5 at least once beforehand so `./install.sh` can auto-install the workflow directly into Alfred's preferences)

### One-Command Setup

```zsh
git clone https://github.com/bonkf/macos-camilladsp-eq.git ~/code/macos-camilladsp-eq
# Optional safeguard on read-only / work clones to prevent accidental pushes:
git -C ~/code/macos-camilladsp-eq remote set-url --push origin no_push
cd ~/code/macos-camilladsp-eq
./install.sh
source ~/.zshrc
```

### What `./install.sh` Does
1. Installs **`switchaudio-osx`** and **`blackhole-2ch`** via Homebrew if not yet installed (and restarts `coreaudiod` once if `BlackHole 2ch` isn't registered yet).
2. Locates `camilladsp` or downloads the official precompiled **`CamillaDSP v4.1.3`** binary (`arm64` / `x86_64`) into `~/.local/bin/camilladsp` (falls back to `cargo install camilladsp --locked` if GitHub releases are blocked on corporate Wi-Fi/VPN), and verifies both `SwitchAudioSource` and `camilladsp` can execute (printing their SHA-256 hashes if blocked by endpoint allowlisting).
3. Installs all YAML presets & `$HOME`-portable scripts to `~/.config/camilladsp/`, validates every preset with `camilladsp -c`, and installs the Swift CoreAudio listener (`camilladsp-watcher.swift`, run directly via `/usr/bin/swift` without ad-hoc binary compilation).
4. Renders and loads `~/Library/LaunchAgents/com.user.camilladsp-autoswitch.plist` & `com.user.camilladsp.plist`.
5. Generates SF Symbol icons, writes a fallback bundle to `~/.config/camilladsp/CamillaDSP-EQ.alfredworkflow` (leaving the Git working tree untouched), and installs the workflow directly into Alfred 5's active preferences directory if Alfred has been opened at least once (preserving any custom hotkey you've configured).
6. Appends `eq-*` shell helper functions to `~/.zshrc` if not already present.

### First-Run & Managed Mac Notes
- **macOS Microphone Permission (TCC):** macOS treats capturing audio from `BlackHole 2ch` as **Microphone** access. On a fresh Mac, run `~/.local/bin/camilladsp ~/.config/camilladsp/active.yml` once interactively in Terminal or iTerm to trigger and approve the Microphone prompt (`Ctrl+C` afterwards, then run `eq-auto`), as headless `launchd` startup cannot present a TCC dialog and may otherwise silently capture zeros.
- **Endpoint Binary Allowlisting & Corporate/MDM Macs:** `camilladsp-watcher.swift` executes via Apple's system-signed `/usr/bin/swift` so no locally compiled binary needs approval. If `SwitchAudioSource` or `camilladsp` execution is blocked, `./install.sh` prints the exact binary path and `SHA-256` hash to request allowlist approval before re-running `./install.sh`. If Homebrew cask installation of `blackhole-2ch` is restricted or GitHub release downloads require proxy auth, install BlackHole 2ch via your org's software center or `.pkg` installer first, then re-run `./install.sh`.

---

## Daily Usage

### Alfred 5 (`eq` keyword)
- **`eq` + `Return`** — Smart toggle:
  - On **Work Desk**: flips **Focal Clear Mg Pro (Harman EQ)** ↔ **Adam A3X (Room EQ)** (and remembers your choice in `~/.config/camilladsp/desk-mode` across reboots/docking).
  - On **Couch**: flips **Audeze LCD-2 Classic (Harman EQ)** ↔ **Flat Bypass (`-7.0 dB`)**.
- **`eq speakers` / `eq focal` / `eq lcd` / `eq off` / `eq auto`** — Jump directly to any profile.
- **Global Hotkey (optional):** Open **Alfred Preferences → Workflows → CamillaDSP Audio EQ**, double-click the **Hotkey** node on the canvas, and bind a shortcut for instant Headphones ↔ Speakers toggling.

### Terminal Helpers
- `eq-status` — Show active macOS output, connected DAC, linked preset, Desk mode, and daemon PIDs
- `eq-toggle` — Flip Focal Clear Mg Pro ↔ Adam A3X Room EQ (Desk) or LCD-2C ↔ Flat (Couch)
- `eq-compare` — Interactive gapless level-matched A/B tester (`[SPACE]` flips EQ ↔ Uncorrected/Stock via `SIGHUP`, `[q]` restores EQ)
- `eq-speakers` / `eq-focal` / `eq-lcd` — Select preset explicitly
- `eq-off` — Level-matched flat bypass (`-7.5 dB` Desk / `-7.0 dB` Couch)
- `eq-auto` — Re-run DAC autodetection manually

---

## Adding Another DAC (e.g., Office Dongle / Desktop Amp)
1. Plug in the DAC and find its exact CoreAudio name:
   ```zsh
   SwitchAudioSource -a -t output
   ```
2. Add a `<device>.yml` preset in `presets/` with `playback.device` set to that exact string.
3. Add the device constant and branch in `scripts/eq-ctl.sh` and `scripts/alfred-filter.py`, then re-run `./install.sh`.

## Uninstall
```zsh
./uninstall.sh
```
Stops both daemons, removes the LaunchAgents, and switches macOS audio output back to direct hardware output.
