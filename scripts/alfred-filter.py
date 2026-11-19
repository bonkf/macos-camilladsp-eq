#!/usr/bin/env python3
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
ENV = dict(
    os.environ,
    PATH=f"{HOME}/.local/bin:{HOME}/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
)
CFG_DIR = os.path.join(HOME, ".config", "camilladsp")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
for _dir in (CFG_DIR, SCRIPT_DIR):
    if _dir not in sys.path and os.path.isdir(_dir):
        sys.path.insert(0, _dir)

from audio_devices import get_default_output_device, list_output_devices  # noqa: E402

ACTIVE_LINK = os.path.join(CFG_DIR, "active.yml")

DESK_DAC = "Schiit USB Audio Gen 2"
COUCH_DAC = "Speaker-Schiit USB Audio Device"
BLACKHOLE = "BlackHole 2ch"


def run_out(cmd):
    try:
        return subprocess.check_output(cmd, env=ENV, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


try:
    outputs = set(list_output_devices())
except Exception:
    outputs = set()

try:
    current_out = get_default_output_device()
except Exception:
    current_out = ""

dsp_running = bool(run_out(["pgrep", "-x", "camilladsp"]))

try:
    active_preset = os.path.basename(os.readlink(ACTIVE_LINK))
except OSError:
    active_preset = "none"

on_desk = DESK_DAC in outputs
on_couch = COUCH_DAC in outputs
eq_routed = (current_out == BLACKHOLE and dsp_running)

is_focal_active = eq_routed and active_preset == "focal_clear_mg.yml"
is_a3x_active = eq_routed and active_preset == "adam_a3x.yml"
is_lcd_active = eq_routed and active_preset == "lcd2c_stock.yml"
is_flat_active = eq_routed and active_preset.endswith("_flat_ab.yml")

if on_desk:
    loc_label = f"Work Desk ({DESK_DAC})"
    if is_focal_active:
        toggle_title = "Toggle → Adam A3X Speakers (Room EQ)"
        toggle_sub = f"Currently ACTIVE: Focal Clear Mg Pro EQ → {DESK_DAC}"
    elif is_a3x_active:
        toggle_title = "Toggle → Focal Clear Mg Pro (Harman EQ)"
        toggle_sub = f"Currently ACTIVE: Adam A3X Room EQ → {DESK_DAC}"
    else:
        toggle_title = "Toggle → Focal Clear Mg Pro (Harman EQ)"
        toggle_sub = f"Currently FLAT Bypass (-7.5 dB) → {DESK_DAC}"
elif on_couch:
    loc_label = f"Couch ({COUCH_DAC})"
    if is_lcd_active:
        toggle_title = "Toggle → Flat / Stock (-7.0 dB)"
        toggle_sub = f"Currently ACTIVE: Audeze LCD-2 Classic EQ → {COUCH_DAC}"
    else:
        toggle_title = "Toggle → Audeze LCD-2 Classic EQ"
        toggle_sub = f"Currently FLAT / Stock (-7.0 dB) → {COUCH_DAC}"
else:
    loc_label = f"Undocked (Output: {current_out or 'Built-in Speakers'})"
    toggle_title = "Toggle Audio EQ (No Schiit DAC Connected)"
    toggle_sub = loc_label

items = [
    {
        "title": toggle_title,
        "subtitle": toggle_sub,
        "arg": "toggle",
        "match": "toggle switch flip",
        "icon": {"path": "toggle.png"},
    },
    {
        "title": ("✓ " if is_a3x_active else "") + "Adam A3X Speakers (Room EQ)",
        "subtitle": f"UMIK-1 6-band nearfield room correction (-6.5 dB preamp) → {DESK_DAC}",
        "arg": "speakers",
        "match": "speakers adam a3x monitors room eq desk",
        "icon": {"path": "speakers.png"},
    },
    {
        "title": ("✓ " if is_focal_active else "") + "Focal Clear Mg Pro (Harman EQ)",
        "subtitle": f"Oratory1990 10-band Harman Over-Ear (-11.2 dB preamp) → {DESK_DAC}",
        "arg": "focal",
        "match": "focal clear mg pro headphones desk jotunheim",
        "icon": {"path": "headphones.png"},
    },
    {
        "title": ("✓ " if is_lcd_active else "") + "Audeze LCD-2 Classic (Harman EQ)",
        "subtitle": f"Oratory1990 10-band Harman Over-Ear (-8.0 dB preamp) → {COUCH_DAC}",
        "arg": "lcd",
        "match": "audeze lcd 2c lcd2c oratory couch modi",
        "icon": {"path": "headphones.png"},
    },
    {
        "title": ("✓ " if is_flat_active else "") + "Flat Bypass (No EQ, Level-Matched)",
        "subtitle": "Uncorrected flat passthrough (-7.5 dB Desk / -7.0 dB Couch)",
        "arg": "off",
        "match": "flat off bypass stock uncorrected",
        "icon": {"path": "icon.png"},
    },
    {
        "title": "Auto-Detect Connected DAC",
        "subtitle": f"Detected: {loc_label}",
        "arg": "auto",
        "match": "auto detect sync refresh",
        "icon": {"path": "auto.png"},
    },
]

print(json.dumps({"items": items}))
