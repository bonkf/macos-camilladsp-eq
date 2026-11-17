#!/bin/zsh
set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

CFG_DIR="$HOME/.config/camilladsp"
ACTIVE_LINK="$CFG_DIR/active.yml"
DESK_MODE_FILE="$CFG_DIR/desk-mode"
PLIST_DSP="$HOME/Library/LaunchAgents/com.user.camilladsp.plist"
UID_NUM="$(id -u)"

DESK_DAC="Schiit USB Audio Gen 2"
COUCH_DAC="Speaker-Schiit USB Audio Device"
BLACKHOLE="BlackHole 2ch"

notify() {
  [[ "${ALFRED_QUIET_NOTIFY:-0}" == "1" ]] && return 0
  local title="$1"
  local msg="$2"
  /usr/bin/osascript -e "display notification \"${msg}\" with title \"${title}\"" >/dev/null 2>&1 || true
}

has_output() {
  local target="$1"
  SwitchAudioSource -a -t output 2>/dev/null | grep -Fxq "$target"
}

get_builtin_speakers() {
  local found
  found="$(SwitchAudioSource -a -t output 2>/dev/null | grep -E 'MacBook .* (Speakers|Lautsprecher)|Mac .* (Speakers|Lautsprecher)|Built-in Output|Internal Speakers' | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    echo "$found"
  else
    echo "MacBook Pro Speakers"
  fi
}

get_desk_mode() {
  if [[ -f "$DESK_MODE_FILE" ]]; then
    local mode
    mode="$(tr -d '[:space:]' < "$DESK_MODE_FILE")"
    if [[ "$mode" == "speakers" || "$mode" == "focal" ]]; then
      echo "$mode"
      return
    fi
  fi
  echo "focal"
}

set_desk_mode() {
  echo "$1" > "$DESK_MODE_FILE"
}

ensure_dsp_running() {
  local preset_file="$1"
  local target="$CFG_DIR/$preset_file"

  local check_out
  if ! check_out="$(camilladsp -c "$target" 2>&1)"; then
    echo "Error: invalid CamillaDSP config: $target" >&2
    echo "$check_out" >&2
    return 1
  fi

  ln -sfn "$target" "$ACTIVE_LINK"

  if pgrep -qx camilladsp; then
    pkill -HUP -x camilladsp
  else
    if ! launchctl print "gui/$UID_NUM/com.user.camilladsp" >/dev/null 2>&1; then
      launchctl bootstrap "gui/$UID_NUM" "$PLIST_DSP" >/dev/null 2>&1 || true
    fi
    launchctl kickstart -kp "gui/$UID_NUM/com.user.camilladsp" >/dev/null 2>&1 || true
  fi
}

stop_dsp() {
  if launchctl print "gui/$UID_NUM/com.user.camilladsp" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID_NUM/com.user.camilladsp" >/dev/null 2>&1 || true
  fi
  pkill -x camilladsp >/dev/null 2>&1 || true
}

activate_eq() {
  local preset_file="$1"
  local label="$2"
  local dac_name="$3"

  ln -sfn "$CFG_DIR/$preset_file" "$ACTIVE_LINK"

  if ! has_output "$BLACKHOLE"; then
    echo "Warning: '$BLACKHOLE' not yet active in CoreAudio (run 'sudo killall -9 coreaudiod' or reboot)." >&2
    if has_output "$dac_name"; then
      SwitchAudioSource -t output -s "$dac_name" >/dev/null
      echo "Fallback direct output -> $dac_name"
    fi
    return 1
  fi

  ensure_dsp_running "$preset_file"
  SwitchAudioSource -t output -s "$BLACKHOLE" >/dev/null
  echo "EQ active: $label ($BLACKHOLE -> $dac_name)"
}

flat_bypass_eq() {
  local builtin_spk
  if has_output "$DESK_DAC"; then
    activate_eq "focal_flat_ab.yml" "Flat Bypass (-7.5 dB, No EQ)" "$DESK_DAC"
  elif has_output "$COUCH_DAC"; then
    activate_eq "lcd2c_flat_ab.yml" "Flat Bypass (-7.0 dB, No EQ)" "$COUCH_DAC"
  else
    builtin_spk="$(get_builtin_speakers)"
    SwitchAudioSource -t output -s "$builtin_spk" >/dev/null
    stop_dsp
    echo "EQ bypassed (Undocked): macOS output -> $builtin_spk"
  fi
}

raw_bypass_eq() {
  local target_out
  target_out="$(get_builtin_speakers)"
  if has_output "$DESK_DAC"; then
    target_out="$DESK_DAC"
  elif has_output "$COUCH_DAC"; then
    target_out="$COUCH_DAC"
  fi

  SwitchAudioSource -t output -s "$target_out" >/dev/null
  stop_dsp
  echo "Raw 0 dB bypass: macOS output -> $target_out"
}

main() {
  local cmd="${1:-status}"
  local active_target="" active_name="" current_out="" key="" mode="" builtin_spk=""
  local out_dev="" dsp_pid="" watch_pid="" desk_mode="" conn_dac=""

  case "$cmd" in
    focal)
      set_desk_mode "focal"
      if has_output "$DESK_DAC"; then
        activate_eq "focal_clear_mg.yml" "Focal Clear Mg Pro (Harman EQ)" "$DESK_DAC"
      else
        echo "Saved Desk preset: Focal Clear Mg Pro (will activate when $DESK_DAC connects)"
      fi
      ;;

    speakers)
      set_desk_mode "speakers"
      if has_output "$DESK_DAC"; then
        activate_eq "adam_a3x.yml" "Adam A3X (Room EQ)" "$DESK_DAC"
      else
        echo "Saved Desk preset: Adam A3X Room EQ (will activate when $DESK_DAC connects)"
      fi
      ;;

    lcd)
      if has_output "$COUCH_DAC"; then
        activate_eq "lcd2c_stock.yml" "Audeze LCD-2 Classic (Harman EQ)" "$COUCH_DAC"
      else
        echo "Couch DAC ($COUCH_DAC) not connected; LCD-2 Classic EQ will activate automatically when docked."
      fi
      ;;

    off)
      flat_bypass_eq
      ;;

    raw)
      raw_bypass_eq
      ;;

    ab)
      active_target="$(readlink "$ACTIVE_LINK" 2>/dev/null || echo '')"
      active_name="${active_target:t}"
      if has_output "$DESK_DAC"; then
        mode="$(get_desk_mode)"
        if [[ "$mode" == "speakers" ]]; then
          if [[ "$active_name" == "adam_a3x.yml" ]]; then
            activate_eq "focal_flat_ab.yml" "Adam A3X — Flat / Uncorrected (-7.5 dB)" "$DESK_DAC"
          else
            activate_eq "adam_a3x.yml" "Adam A3X — Room EQ (-6.5 dB)" "$DESK_DAC"
          fi
        else
          if [[ "$active_name" == "focal_clear_mg.yml" ]]; then
            activate_eq "focal_flat_ab.yml" "Focal Clear Mg Pro — Flat / Stock (-7.5 dB)" "$DESK_DAC"
          else
            activate_eq "focal_clear_mg.yml" "Focal Clear Mg Pro — Harman EQ (-11.2 dB)" "$DESK_DAC"
          fi
        fi
      elif has_output "$COUCH_DAC"; then
        if [[ "$active_name" == "lcd2c_stock.yml" ]]; then
          activate_eq "lcd2c_flat_ab.yml" "LCD-2 Classic — Flat / Stock (-7.0 dB)" "$COUCH_DAC"
        else
          activate_eq "lcd2c_stock.yml" "Audeze LCD-2 Classic — Harman EQ (-8.0 dB)" "$COUCH_DAC"
        fi
      else
        echo "No Schiit DAC connected ($DESK_DAC or $COUCH_DAC)." >&2
        return 1
      fi
      ;;

    compare)
      if has_output "$DESK_DAC" && [[ "$(get_desk_mode)" == "speakers" ]]; then
        echo "Gapless Level-Matched A/B Compare (Adam A3X) — tap [SPACE] to flip Room EQ <-> Uncorrected, [q] to quit (restores Room EQ):"
      elif has_output "$DESK_DAC"; then
        echo "Gapless Level-Matched A/B Compare (Focal Clear Mg Pro) — tap [SPACE] to flip Harman EQ <-> Stock, [q] to quit (restores EQ):"
      else
        echo "Gapless Level-Matched A/B Compare — tap [SPACE] to flip EQ <-> Stock, [q] to quit (restores EQ):"
      fi
      while true; do
        read -s -r -k 1 key || break
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
          if has_output "$DESK_DAC"; then
            if [[ "$(get_desk_mode)" == "speakers" ]]; then
              activate_eq "adam_a3x.yml" "Adam A3X (Room EQ)" "$DESK_DAC"
            else
              activate_eq "focal_clear_mg.yml" "Focal Clear Mg Pro (Harman EQ)" "$DESK_DAC"
            fi
          elif has_output "$COUCH_DAC"; then
            activate_eq "lcd2c_stock.yml" "Audeze LCD-2 Classic (Harman EQ)" "$COUCH_DAC"
          fi
          break
        fi
        main ab
      done
      ;;

    toggle)
      current_out="$(SwitchAudioSource -c -t output 2>/dev/null || echo '')"
      active_target="$(readlink "$ACTIVE_LINK" 2>/dev/null || echo '')"
      active_name="${active_target:t}"

      if has_output "$DESK_DAC"; then
        if [[ "$current_out" == "$BLACKHOLE" && "$active_name" == "focal_clear_mg.yml" ]]; then
          set_desk_mode "speakers"
          activate_eq "adam_a3x.yml" "Adam A3X (Room EQ)" "$DESK_DAC"
          notify "Speaker Room EQ Active" "Adam A3X (UMIK-1 EQ) → $DESK_DAC"
        else
          set_desk_mode "focal"
          activate_eq "focal_clear_mg.yml" "Focal Clear Mg Pro (Harman EQ)" "$DESK_DAC"
          notify "Headphone EQ Active" "Focal Clear Mg Pro → $DESK_DAC"
        fi
      elif has_output "$COUCH_DAC"; then
        if [[ "$current_out" == "$BLACKHOLE" && "$active_name" == "lcd2c_stock.yml" ]]; then
          activate_eq "lcd2c_flat_ab.yml" "Flat Bypass (-7.0 dB)" "$COUCH_DAC"
          notify "EQ Off — Flat (-7.0 dB)" "Stock / Flat → $COUCH_DAC"
        else
          activate_eq "lcd2c_stock.yml" "Audeze LCD-2 Classic (Harman EQ)" "$COUCH_DAC"
          notify "Headphone EQ Active" "Audeze LCD-2 Classic → $COUCH_DAC"
        fi
      else
        echo "No Schiit DAC connected ($DESK_DAC or $COUCH_DAC)." >&2
        notify "Audio EQ" "No Schiit DAC connected"
        return 1
      fi
      ;;

    auto)
      if has_output "$DESK_DAC"; then
        mode="$(get_desk_mode)"
        if [[ "$mode" == "speakers" ]]; then
          activate_eq "adam_a3x.yml" "Adam A3X (Room EQ)" "$DESK_DAC"
        else
          activate_eq "focal_clear_mg.yml" "Focal Clear Mg Pro (Harman EQ)" "$DESK_DAC"
        fi
      elif has_output "$COUCH_DAC"; then
        activate_eq "lcd2c_stock.yml" "Audeze LCD-2 Classic (Harman EQ)" "$COUCH_DAC"
      else
        stop_dsp
        current_out="$(SwitchAudioSource -c -t output 2>/dev/null || echo '')"
        if [[ "$current_out" == "$BLACKHOLE" ]]; then
          builtin_spk="$(get_builtin_speakers)"
          SwitchAudioSource -t output -s "$builtin_spk" >/dev/null
          echo "Auto-routing (Undocked): switched output from $BLACKHOLE -> $builtin_spk"
        else
          echo "Auto-routing (Undocked): keeping current output ($current_out)"
        fi
      fi
      ;;

    status)
      out_dev="$(SwitchAudioSource -c -t output 2>/dev/null || echo 'unknown')"
      active_target="$(readlink "$ACTIVE_LINK" 2>/dev/null || echo 'none')"
      active_name="${active_target:t}"
      dsp_pid="$(pgrep -x camilladsp | tr '\n' ' ' || true)"
      watch_pid="$(pgrep -x camilladsp-watcher | tr '\n' ' ' || true)"
      desk_mode="$(get_desk_mode)"

      if has_output "$DESK_DAC"; then
        conn_dac="$DESK_DAC (Work Desk)"
      elif has_output "$COUCH_DAC"; then
        conn_dac="$COUCH_DAC (Couch)"
      else
        conn_dac="none (Undocked)"
      fi

      echo "macOS Output  : $out_dev"
      if [[ "$out_dev" == "$BLACKHOLE" && -n "$dsp_pid" ]]; then
        case "$active_name" in
          adam_a3x.yml)       echo "EQ Routing    : ACTIVE (Adam A3X Room EQ)" ;;
          focal_clear_mg.yml) echo "EQ Routing    : ACTIVE (Focal Clear Mg Pro Harman EQ)" ;;
          lcd2c_stock.yml)    echo "EQ Routing    : ACTIVE (Audeze LCD-2 Classic Harman EQ)" ;;
          *_flat_ab.yml)      echo "EQ Routing    : FLAT BYPASS (level-matched, no EQ)" ;;
          *)                  echo "EQ Routing    : ACTIVE ($active_name)" ;;
        esac
      else
        echo "EQ Routing    : RAW BYPASS"
      fi
      echo "Connected DAC : $conn_dac"
      echo "Linked Preset : $active_name"
      echo "Desk Mode     : $desk_mode"
      if [[ -n "$dsp_pid" ]]; then
        echo "CamillaDSP    : running (PID ${dsp_pid% })"
      else
        echo "CamillaDSP    : stopped"
      fi
      if [[ -n "$watch_pid" ]]; then
        echo "Auto-Watcher  : running (PID ${watch_pid% })"
      else
        echo "Auto-Watcher  : stopped"
      fi
      ;;

    *)
      echo "Usage: $0 {toggle|ab|compare|focal|speakers|lcd|off|raw|auto|status}" >&2
      return 1
      ;;
  esac
}

main "$@"
