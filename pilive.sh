#!/bin/sh
# PILIVE: Single-file sh app to livestream Raspberry Pi screen to YouTube via RTMP.
# GUI with yad (preferred) or zenity; falls back to CLI prompts.
# Author: You and your future self.

APP_NAME="PILIVE"
CONFIG_FILE="${HOME}/.pilive.conf"
PID_FILE="${HOME}/.pilive.pid"
LOG_FILE="${HOME}/.pilive.log"

# -------- Defaults (can be overridden in ~/.pilive.conf via Config) --------
RTMP_URL_DEFAULT="rtmp://a.rtmp.youtube.com/live2"
STREAM_KEY_DEFAULT=""
RESOLUTION_DEFAULT="1280x720"
FRAMERATE_DEFAULT="30"
DISPLAY_DEFAULT=":0.0"
VIDEO_CODEC_DEFAULT="libx264"     # On Pi, consider h264_v4l2m2m for lower CPU
PRESET_DEFAULT="veryfast"
BITRATE_DEFAULT="2500k"
MAXRATE_DEFAULT="2500k"
BUFSIZE_DEFAULT="5000k"
AUDIO_DEVICE_DEFAULT="anullsrc"   # "anullsrc" = silent; for mic use "alsa:default" or "hw:1,0"

# -------- Helpers --------
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }
warn() { printf '%s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }

ensure_dirs() {
  umask 077
  touch "$LOG_FILE" 2>/dev/null || true
  chmod 600 "$LOG_FILE" 2>/dev/null || true
}

load_config() {
  # Load with defaults first
  RTMP_URL="$RTMP_URL_DEFAULT"
  STREAM_KEY="$STREAM_KEY_DEFAULT"
  RESOLUTION="$RESOLUTION_DEFAULT"
  FRAMERATE="$FRAMERATE_DEFAULT"
  DISPLAY_ID="$DISPLAY_DEFAULT"
  VIDEO_CODEC="$VIDEO_CODEC_DEFAULT"
  PRESET="$PRESET_DEFAULT"
  BITRATE="$BITRATE_DEFAULT"
  MAXRATE="$MAXRATE_DEFAULT"
  BUFSIZE="$BUFSIZE_DEFAULT"
  AUDIO_DEVICE="$AUDIO_DEVICE_DEFAULT"

  if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
      case "$key" in
        RTMP_URL) RTMP_URL="$value" ;;
        STREAM_KEY) STREAM_KEY="$value" ;;
        RESOLUTION) RESOLUTION="$value" ;;
        FRAMERATE) FRAMERATE="$value" ;;
        DISPLAY_ID) DISPLAY_ID="$value" ;;
        VIDEO_CODEC) VIDEO_CODEC="$value" ;;
        PRESET) PRESET="$value" ;;
        BITRATE) BITRATE="$value" ;;
        MAXRATE) MAXRATE="$value" ;;
        BUFSIZE) BUFSIZE="$value" ;;
        AUDIO_DEVICE) AUDIO_DEVICE="$value" ;;
      esac
    done < "$CONFIG_FILE"
  fi
}

save_config() {
  umask 077
  cat > "$CONFIG_FILE" <<EOF
# ${APP_NAME} configuration
RTMP_URL=${RTMP_URL}
STREAM_KEY=${STREAM_KEY}
RESOLUTION=${RESOLUTION}
FRAMERATE=${FRAMERATE}
DISPLAY_ID=${DISPLAY_ID}
VIDEO_CODEC=${VIDEO_CODEC}
PRESET=${PRESET}
BITRATE=${BITRATE}
MAXRATE=${MAXRATE}
BUFSIZE=${BUFSIZE}
AUDIO_DEVICE=${AUDIO_DEVICE}
EOF
  chmod 600 "$CONFIG_FILE"
}

is_running() {
  [ -f "$PID_FILE" ] || return 1
  PID="$(cat "$PID_FILE" 2>/dev/null || echo)"
  [ -n "$PID" ] || return 1
  kill -0 "$PID" 2>/dev/null
}

pid() {
  cat "$PID_FILE" 2>/dev/null
}

check_deps() {
  command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is required. Install with: sudo apt update && sudo apt install -y ffmpeg"
}

# -------- Streaming control --------
start_stream() {
  if is_running; then
    warn "Stream already running (PID $(pid))."
    return 0
  fi

  [ -n "$STREAM_KEY" ] || die "STREAM_KEY is empty. Open Config and set your YouTube stream key."

  [ -n "${DISPLAY:-}" ] || die "Screen capture requires an active X11 display. Terminal controls remain available on headless systems."
  command -v xdpyinfo >/dev/null 2>&1 || die "Install x11-utils to verify the X11 display before streaming."
  xdpyinfo -display "$DISPLAY_ID" >/dev/null 2>&1 || die "Cannot access selected X11 display."
  case "$FRAMERATE" in ''|*[!0-9]*) die "Framerate must be an integer." ;; esac
  [ "$FRAMERATE" -ge 1 ] && [ "$FRAMERATE" -le 120 ] || die "Framerate must be 1-120."
  GOP=$((FRAMERATE * 2))
  set -- ffmpeg -y -f x11grab -video_size "$RESOLUTION" -framerate "$FRAMERATE" -i "$DISPLAY_ID"
  if [ "$AUDIO_DEVICE" = anullsrc ]; then
    set -- "$@" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100
  else
    set -- "$@" -f alsa -i "${AUDIO_DEVICE#alsa:}"
  fi
  set -- "$@" -c:v "$VIDEO_CODEC" -preset "$PRESET" -b:v "$BITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" -g "$GOP" -pix_fmt yuv420p -tune zerolatency -f flv "$RTMP_URL/$STREAM_KEY"
  log "Starting screen stream (destination and key omitted)."
  # ffmpeg stderr can contain the destination key. Do not persist it.
  "$@" >/dev/null 2>&1 &
  FF_PID=$!
  echo "$FF_PID" > "$PID_FILE"
  printf '%s\n' "Streaming started (PID $FF_PID)."
}

stop_stream() {
  if ! is_running; then
    warn "No active stream."
    return 0
  fi
  P="$(pid)"
  log "Stopping stream PID $P"
  kill -TERM "$P" 2>/dev/null || true
  # Wait up to 5s
  for i in 1 2 3 4 5; do
    kill -0 "$P" 2>/dev/null || break
    sleep 1
  done
  kill -KILL "$P" 2>/dev/null || true
  rm -f "$PID_FILE"
  printf '%s\n' "Streaming stopped."
}

pause_stream() {
  if ! is_running; then warn "No active stream."; return 0; fi
  P="$(pid)"
  kill -STOP "$P" 2>/dev/null || warn "Failed to pause."
  printf '%s\n' "Paused stream (SIGSTOP)."
}

resume_stream() {
  if ! is_running; then warn "No active stream."; return 0; fi
  P="$(pid)"
  kill -CONT "$P" 2>/dev/null || warn "Failed to resume."
  printf '%s\n' "Resumed stream (SIGCONT)."
}

# -------- GUI (yad preferred, zenity fallback) --------
gui_config_yad() {
  load_config
  RES="$(yad --form --title="${APP_NAME} Config" --center \
    --field="RTMP URL":TXT "${RTMP_URL}" \
    --field="Stream Key":H "${STREAM_KEY}" \
    --field="Resolution (WxH)":TXT "${RESOLUTION}" \
    --field="Framerate (fps)":NUM "${FRAMERATE}" \
    --field="Display (e.g., :0.0)":TXT "${DISPLAY_ID}" \
    --field="Video codec (libx264/h264_v4l2m2m)":CB "${VIDEO_CODEC}!libx264!h264_v4l2m2m" \
    --field="Preset":CB "${PRESET}!ultrafast!superfast!veryfast!faster!fast!medium" \
    --field="Bitrate (e.g., 2500k)":TXT "${BITRATE}" \
    --field="Maxrate":TXT "${MAXRATE}" \
    --field="Bufsize":TXT "${BUFSIZE}" \
    --field="Audio (anullsrc/alsa:dev)":TXT "${AUDIO_DEVICE}" \
    --separator="|")" || return 1

  RTMP_URL=$(printf '%s' "$RES" | cut -d'|' -f1)
  STREAM_KEY=$(printf '%s' "$RES" | cut -d'|' -f2)
  RESOLUTION=$(printf '%s' "$RES" | cut -d'|' -f3)
  FRAMERATE=$(printf '%s' "$RES" | cut -d'|' -f4)
  DISPLAY_ID=$(printf '%s' "$RES" | cut -d'|' -f5)
  VIDEO_CODEC=$(printf '%s' "$RES" | cut -d'|' -f6)
  PRESET=$(printf '%s' "$RES" | cut -d'|' -f7)
  BITRATE=$(printf '%s' "$RES" | cut -d'|' -f8)
  MAXRATE=$(printf '%s' "$RES" | cut -d'|' -f9)
  BUFSIZE=$(printf '%s' "$RES" | cut -d'|' -f10)
  AUDIO_DEVICE=$(printf '%s' "$RES" | cut -d'|' -f11)

  save_config
}

gui_loop_yad() {
  while :; do
    yad --title="$APP_NAME" --undecorated --sticky --on-top --skip-taskbar --center \
      --buttons-layout=center \
      --button="Start":0 --button="Pause":1 --button="Resume":2 \
      --button="Stop":3 --button="Config":4 --button="Quit":5
    case "$?" in
      0) load_config; check_deps; start_stream ;;
      1) pause_stream ;;
      2) resume_stream ;;
      3) stop_stream ;;
      4) gui_config_yad ;;
      5|252) break ;; # 252 = window closed
      *) : ;;
    esac
  done
}

gui_config_zenity() {
  load_config
  RES="$(zenity --forms --title="${APP_NAME} Config" --text="YouTube settings" \
    --add-entry="RTMP URL" \
    --add-password="Stream Key" \
    --add-entry="Resolution (WxH)" \
    --add-entry="Framerate (fps)" \
    --add-entry="Display (e.g., :0.0)" \
    --add-entry="Video codec (libx264/h264_v4l2m2m)" \
    --add-entry="Preset" \
    --add-entry="Bitrate (e.g., 2500k)" \
    --add-entry="Maxrate" \
    --add-entry="Bufsize" \
    --add-entry="Audio (anullsrc/alsa:dev)" \
    --separator="|")" || return 1

  RTMP_URL=$(printf '%s' "$RES" | cut -d'|' -f1)
  STREAM_KEY=$(printf '%s' "$RES" | cut -d'|' -f2)
  RESOLUTION=$(printf '%s' "$RES" | cut -d'|' -f3)
  FRAMERATE=$(printf '%s' "$RES" | cut -d'|' -f4)
  DISPLAY_ID=$(printf '%s' "$RES" | cut -d'|' -f5)
  VIDEO_CODEC=$(printf '%s' "$RES" | cut -d'|' -f6)
  PRESET=$(printf '%s' "$RES" | cut -d'|' -f7)
  BITRATE=$(printf '%s' "$RES" | cut -d'|' -f8)
  MAXRATE=$(printf '%s' "$RES" | cut -d'|' -f9)
  BUFSIZE=$(printf '%s' "$RES" | cut -d'|' -f10)
  AUDIO_DEVICE=$(printf '%s' "$RES" | cut -d'|' -f11)

  save_config
}

gui_loop_zenity() {
  while :; do
    CHOICE="$(zenity --list --title="${APP_NAME}" --text="Select an action" \
      --column="Action" Start Pause Resume Stop Config Quit)"
    case "$CHOICE" in
      Start) load_config; check_deps; start_stream ;;
      Pause) pause_stream ;;
      Resume) resume_stream ;;
      Stop) stop_stream ;;
      Config) gui_config_zenity ;;
      Quit|"") break ;;
      *) : ;;
    esac
  done
}

# -------- CLI mode --------
cli_usage() {
  cat <<EOF
${APP_NAME} (single-file sh)
Usage: $0 [gui|start|pause|resume|stop|config|status]

Commands:
  gui      Launch button UI (yad or zenity)
  start    Start streaming to YouTube
  pause    Pause stream (SIGSTOP)
  resume   Resume stream (SIGCONT)
  stop     Stop streaming
  config   Configure settings (CLI prompts)
  status   Show running status
EOF
}

cli_config() {
  load_config
  printf "RTMP URL [%s]: " "$RTMP_URL"; read -r v; [ -n "$v" ] && RTMP_URL="$v"
  printf "Stream Key [hidden, Enter keeps current]: "
  old_stty=$(stty -g 2>/dev/null || true)
  [ -z "$old_stty" ] || stty -echo
  read -r v
  [ -z "$old_stty" ] || stty "$old_stty"
  printf '\n'
  [ -z "$v" ] || STREAM_KEY="$v"
  printf "Resolution (WxH) [%s]: " "$RESOLUTION"; read -r v; [ -n "$v" ] && RESOLUTION="$v"
  printf "Framerate (fps) [%s]: " "$FRAMERATE"; read -r v; [ -n "$v" ] && FRAMERATE="$v"
  printf "Display (e.g., :0.0) [%s]: " "$DISPLAY_ID"; read -r v; [ -n "$v" ] && DISPLAY_ID="$v"
  printf "Video codec [%s]: " "$VIDEO_CODEC"; read -r v; [ -n "$v" ] && VIDEO_CODEC="$v"
  printf "Preset [%s]: " "$PRESET"; read -r v; [ -n "$v" ] && PRESET="$v"
  printf "Bitrate [%s]: " "$BITRATE"; read -r v; [ -n "$v" ] && BITRATE="$v"
  printf "Maxrate [%s]: " "$MAXRATE"; read -r v; [ -n "$v" ] && MAXRATE="$v"
  printf "Bufsize [%s]: " "$BUFSIZE"; read -r v; [ -n "$v" ] && BUFSIZE="$v"
  printf "Audio (anullsrc/alsa:dev) [%s]: " "$AUDIO_DEVICE"; read -r v; [ -n "$v" ] && AUDIO_DEVICE="$v"
  save_config
}

status() {
  if is_running; then
    echo "Status: RUNNING (PID $(pid))"
  else
    echo "Status: STOPPED"
  fi
}

cli_menu() {
  while :; do
    printf '\nPILIVE\n1 Status\n2 Configure\n3 Start X11 stream\n4 Pause\n5 Resume\n6 Stop\n7 Quit\nChoice: '
    read -r choice || return 0
    case "$choice" in
      1) status ;;
      2) cli_config ;;
      3) (load_config; check_deps; start_stream) ;;
      4) pause_stream ;;
      5) resume_stream ;;
      6) stop_stream ;;
      7|q|Q) return 0 ;;
      *) echo "Choose 1-7." ;;
    esac
  done
}
has_desktop() { [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; }

# -------- Main --------
ensure_dirs
CMD="${1:-gui}"

case "$CMD" in
  gui)
    if has_desktop && command -v yad >/dev/null 2>&1; then
      gui_loop_yad
    elif has_desktop && command -v zenity >/dev/null 2>&1; then
      gui_loop_zenity
    else
      warn "Neither yad nor zenity found. Falling back to CLI."
      cli_menu
    fi
    ;;
  start) load_config; check_deps; start_stream ;;
  pause) pause_stream ;;
  resume) resume_stream ;;
  stop) stop_stream ;;
  config)
    if has_desktop && command -v yad >/dev/null 2>&1; then gui_config_yad
    elif has_desktop && command -v zenity >/dev/null 2>&1; then gui_config_zenity
    else cli_config
    fi
    ;;
  terminal) cli_menu ;;
  status) status ;;
  *) cli_usage ;;
esac
