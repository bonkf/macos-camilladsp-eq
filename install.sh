#!/bin/zsh
set -euo pipefail

REPO_DIR="${0:A:h}"
CFG_DIR="$HOME/.config/camilladsp"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
LOCAL_BIN="$HOME/.local/bin"
UID_NUM="$(id -u)"
CAMILLADSP_VERSION="v4.1.3"
BLACKHOLE_PKG_URL="https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg"
BLACKHOLE_PKG_SHA256="57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"

export PATH="$LOCAL_BIN:$HOME/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

info() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m ✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m !\033[0m %s\n" "$*"; }

die_blocked_bin() {
  local bin_path="$1"
  local real_path="${bin_path:A}"
  local sha256
  sha256="$(shasum -a 256 "$bin_path" 2>/dev/null | awk '{print $1}' || true)"
  echo "" >&2
  echo "Error: Failed to execute '$bin_path'." >&2
  if [[ "$real_path" != "$bin_path" ]]; then
    echo "  Resolved path : $real_path" >&2
  fi
  echo "  Binary path   : $bin_path" >&2
  echo "  SHA-256       : ${sha256:-unavailable}" >&2
  echo "If this Mac enforces endpoint binary allowlisting (e.g. Santa / MDM), get the SHA-256 above approved before re-running ./install.sh." >&2
  exit 1
}

# 1. Check Xcode Command Line Tools (swift + python3)
if ! command -v swift >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "Error: 'swift' and/or 'python3' not found. Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
fi

# 2. Check / install BlackHole 2ch (official signed .pkg)
if [[ ! -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]]; then
  info "Downloading BlackHole 2ch v0.7.1 installer from Existential Audio..."
  TMP_PKG_DIR="$(mktemp -d -t blackhole_pkg.XXXXXX)"
  TMP_PKG="$TMP_PKG_DIR/BlackHole2ch-0.7.1.pkg"
  if ! curl -fsSL "$BLACKHOLE_PKG_URL" -o "$TMP_PKG"; then
    rm -rf "$TMP_PKG_DIR"
    echo "Error: Could not download BlackHole 2ch from $BLACKHOLE_PKG_URL." >&2
    echo "Install BlackHole 2ch via .pkg first (https://existential.audio/blackhole/), then re-run ./install.sh." >&2
    exit 1
  fi

  ACTUAL_PKG_SHA256="$(shasum -a 256 "$TMP_PKG" | awk '{print $1}')"
  if [[ "$ACTUAL_PKG_SHA256" != "$BLACKHOLE_PKG_SHA256" ]]; then
    rm -rf "$TMP_PKG_DIR"
    echo "Error: SHA-256 mismatch for downloaded BlackHole2ch-0.7.1.pkg!" >&2
    echo "  Expected : $BLACKHOLE_PKG_SHA256" >&2
    echo "  Actual   : $ACTUAL_PKG_SHA256" >&2
    exit 1
  fi

  if ! PKG_SIG_OUT="$(pkgutil --check-signature "$TMP_PKG" 2>&1)" || ! grep -Fq "Developer ID Installer: Existential Audio Inc." <<< "$PKG_SIG_OUT"; then
    rm -rf "$TMP_PKG_DIR"
    echo "Error: Apple Developer ID signature verification failed for BlackHole2ch-0.7.1.pkg!" >&2
    echo "$PKG_SIG_OUT" >&2
    exit 1
  fi
  ok "Verified BlackHole2ch-0.7.1.pkg (SHA-256 + Developer ID signature)"

  info "Installing BlackHole 2ch virtual audio driver (prompts for sudo)..."
  if ! sudo installer -pkg "$TMP_PKG" -target /; then
    rm -rf "$TMP_PKG_DIR"
    echo "Error: Failed to install BlackHole 2ch via 'sudo installer -pkg'." >&2
    exit 1
  fi
  rm -rf "$TMP_PKG_DIR"
fi

if ! "$REPO_DIR/scripts/audio_devices.py" list 2>/dev/null | grep -Fxq "BlackHole 2ch"; then
  if [[ -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]]; then
    info "Reloading macOS coreaudiod so 'BlackHole 2ch' appears immediately (prompts for sudo)..."
    sudo killall -9 coreaudiod || true
    sleep 1.5
  fi
fi
ok "BlackHole 2ch driver ready"

# 3. Locate or install CamillaDSP
CAMILLADSP_BIN="$(command -v camilladsp || true)"
if [[ -z "$CAMILLADSP_BIN" ]]; then
  mkdir -p "$LOCAL_BIN"
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" ]]; then
    TARBALL="camilladsp-macos-aarch64.tar.gz"
  else
    TARBALL="camilladsp-macos-amd64.tar.gz"
  fi
  URL="https://github.com/HEnquist/camilladsp/releases/download/${CAMILLADSP_VERSION}/${TARBALL}"
  info "Downloading precompiled CamillaDSP ${CAMILLADSP_VERSION} (${ARCH}) -> $LOCAL_BIN/camilladsp..."
  TMP_TAR="$(mktemp -t camilladsp.XXXXXX.tar.gz)"
  if curl -fsSL "$URL" -o "$TMP_TAR"; then
    tar -xzf "$TMP_TAR" -C "$LOCAL_BIN" camilladsp
    rm -f "$TMP_TAR"
    chmod +x "$LOCAL_BIN/camilladsp"
    xattr -d com.apple.quarantine "$LOCAL_BIN/camilladsp" 2>/dev/null || true
    CAMILLADSP_BIN="$LOCAL_BIN/camilladsp"
  else
    rm -f "$TMP_TAR"
    if command -v cargo >/dev/null 2>&1; then
      info "Release download blocked/offline; building camilladsp from source via cargo..."
      cargo install camilladsp --locked
      CAMILLADSP_BIN="$HOME/.cargo/bin/camilladsp"
    else
      echo "Error: Could not download CamillaDSP from GitHub and 'cargo' is not installed." >&2
      exit 1
    fi
  fi
fi
if ! "$CAMILLADSP_BIN" --version >/dev/null 2>&1; then
  die_blocked_bin "$CAMILLADSP_BIN"
fi
ok "CamillaDSP binary: $CAMILLADSP_BIN ($("$CAMILLADSP_BIN" --version))"

# 4. Install presets, scripts, and CoreAudio watcher
info "Installing presets and control scripts to $CFG_DIR..."
mkdir -p "$CFG_DIR"
cp "$REPO_DIR"/presets/*.yml "$CFG_DIR/"
cp "$REPO_DIR"/scripts/audio_devices.py "$CFG_DIR/audio_devices.py"
cp "$REPO_DIR"/scripts/eq-ctl.sh "$CFG_DIR/eq-ctl.sh"
cp "$REPO_DIR"/scripts/alfred-filter.py "$CFG_DIR/alfred-filter.py"
cp "$REPO_DIR"/scripts/sync-audio.sh "$CFG_DIR/sync-audio.sh"
cp "$REPO_DIR"/scripts/toggle-eq.sh "$CFG_DIR/toggle-eq.sh"
cp "$REPO_DIR"/watcher/camilladsp-watcher.swift "$CFG_DIR/camilladsp-watcher.swift"
rm -f "$CFG_DIR/camilladsp-watcher"
chmod +x "$CFG_DIR/audio_devices.py" "$CFG_DIR/eq-ctl.sh" "$CFG_DIR/alfred-filter.py" "$CFG_DIR/sync-audio.sh" "$CFG_DIR/toggle-eq.sh"

[[ -f "$CFG_DIR/desk-mode" ]] || echo "focal" > "$CFG_DIR/desk-mode"
[[ -L "$CFG_DIR/active.yml" ]] || ln -sfn "$CFG_DIR/focal_clear_mg.yml" "$CFG_DIR/active.yml"

for yml in "$CFG_DIR"/*.yml; do
  [[ "${yml:t}" == "active.yml" ]] && continue
  "$CAMILLADSP_BIN" -c "$yml" >/dev/null
done
ok "Validated all CamillaDSP YAML presets"
ok "Installed CoreAudio watcher ($CFG_DIR/camilladsp-watcher.swift)"

# 5. Render & load LaunchAgents
info "Configuring macOS LaunchAgents in $LAUNCH_DIR..."
mkdir -p "$LAUNCH_DIR"

sed -e "s|__CAMILLADSP_BIN__|$CAMILLADSP_BIN|g" \
    -e "s|__HOME__|$HOME|g" \
    "$REPO_DIR/launchd/com.user.camilladsp.plist.tmpl" > "$LAUNCH_DIR/com.user.camilladsp.plist"

sed -e "s|__HOME__|$HOME|g" \
    "$REPO_DIR/launchd/com.user.camilladsp-autoswitch.plist.tmpl" > "$LAUNCH_DIR/com.user.camilladsp-autoswitch.plist"

plutil -lint "$LAUNCH_DIR/com.user.camilladsp.plist" "$LAUNCH_DIR/com.user.camilladsp-autoswitch.plist" >/dev/null

launchctl bootout "gui/$UID_NUM/com.user.camilladsp" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_NUM/com.user.camilladsp-autoswitch" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_DIR/com.user.camilladsp-autoswitch.plist"
ok "LaunchAgent com.user.camilladsp-autoswitch active"

# 6. Build & install Alfred 5 Workflow (preserves custom hotkey if already configured)
info "Building Alfred 5 workflow icons & bundle..."
TMP_WF="$(mktemp -d -t alfred_eq_wf.XXXXXX)"
swift "$REPO_DIR/alfred/gen_icons.swift" "$TMP_WF"
cp "$REPO_DIR/alfred/info.plist" "$TMP_WF/info.plist"
rm -f "$CFG_DIR/CamillaDSP-EQ.alfredworkflow"
(cd "$TMP_WF" && /usr/bin/zip -q -r "$CFG_DIR/CamillaDSP-EQ.alfredworkflow" .)

ALFRED_PREFS_JSON="$HOME/Library/Application Support/Alfred/prefs.json"
if [[ -f "$ALFRED_PREFS_JSON" ]]; then
  ALFRED_PREFS_DIR="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("current",""))' "$ALFRED_PREFS_JSON" 2>/dev/null || true)"
  if [[ -n "$ALFRED_PREFS_DIR" && -d "$ALFRED_PREFS_DIR" ]]; then
    WF_DEST="$ALFRED_PREFS_DIR/workflows/user.workflow.camilladsp-eq"
    mkdir -p "$WF_DEST"
    if [[ -f "$WF_DEST/info.plist" ]]; then
      python3 - "$WF_DEST/info.plist" "$TMP_WF/info.plist" <<'PY'
import plistlib, sys
old_p, new_p = sys.argv[1], sys.argv[2]
with open(old_p, "rb") as f: old_d = plistlib.load(f)
with open(new_p, "rb") as f: new_d = plistlib.load(f)
old_hk = next((o["config"] for o in old_d.get("objects", []) if o.get("type") == "alfred.workflow.trigger.hotkey"), None)
if old_hk and old_hk.get("hotkey", 0) != 0:
    for o in new_d.get("objects", []):
        if o.get("type") == "alfred.workflow.trigger.hotkey":
            o["config"].update(old_hk)
with open(new_p, "wb") as f: plistlib.dump(new_d, f)
PY
    fi
    cp "$TMP_WF"/* "$WF_DEST/"
    ok "Installed Alfred 5 workflow -> $WF_DEST (keyword: 'eq')"
  else
    warn "Alfred prefs folder not found; double-click $CFG_DIR/CamillaDSP-EQ.alfredworkflow after opening Alfred."
  fi
else
  warn "Alfred 5 not detected yet; double-click $CFG_DIR/CamillaDSP-EQ.alfredworkflow anytime to import."
fi
rm -rf "$TMP_WF"

# 7. Add shell aliases to ~/.zshrc idempotently
ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"
if ! grep -Fq "eq-ctl.sh" "$ZSHRC"; then
  info "Appending eq-* shell functions to $ZSHRC..."
  cat >> "$ZSHRC" <<'EOF'

# CamillaDSP Audio EQ Helpers
eq-toggle()   { "$HOME/.config/camilladsp/eq-ctl.sh" toggle; }
eq-ab()       { "$HOME/.config/camilladsp/eq-ctl.sh" ab; }
eq-compare()  { "$HOME/.config/camilladsp/eq-ctl.sh" compare; }
eq-focal()    { "$HOME/.config/camilladsp/eq-ctl.sh" focal; }
eq-speakers() { "$HOME/.config/camilladsp/eq-ctl.sh" speakers; }
eq-lcd()      { "$HOME/.config/camilladsp/eq-ctl.sh" lcd; }
eq-off()      { "$HOME/.config/camilladsp/eq-ctl.sh" off; }
eq-auto()     { "$HOME/.config/camilladsp/eq-ctl.sh" auto; }
eq-status()   { "$HOME/.config/camilladsp/eq-ctl.sh" status; }
EOF
  ok "Added eq-* helpers to ~/.zshrc"
else
  ok "Shell helpers already present in ~/.zshrc"
fi

# 8. Run initial hardware detection & print status
echo ""
"$CFG_DIR/eq-ctl.sh" auto
echo ""
"$CFG_DIR/eq-ctl.sh" status
