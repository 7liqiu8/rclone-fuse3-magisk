#!/system/bin/sh

MODPATH=${MODPATH:-/data/adb/modules/rclone}

log_msg() {
  echo "$1"
}

load_env() {
  log_msg "Loading Environment Variables"
  log_msg "  * 默认(Predefined): $MODPATH/env"
  set -a
  . "$MODPATH/env"
  set +a

  if [ -n "$RCLONE_CONFIG_DIR" ] && [ -f "$RCLONE_CONFIG_DIR/env" ]; then
    log_msg "  * 自定义(Customized): $RCLONE_CONFIG_DIR/env"
    set -a
    . "$RCLONE_CONFIG_DIR/env"
    set +a
  fi
}

pid_is_running() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

stop_pid_file() {
  NAME="$1"
  PIDFILE="$2"

  if [ ! -f "$PIDFILE" ]; then
    return 0
  fi

  PID="$(cat "$PIDFILE" 2>/dev/null)"
  rm -f "$PIDFILE"

  if pid_is_running "$PID"; then
    log_msg "$NAME is running with PID($PID). Stopping..."
    pkill -P "$PID" 2>/dev/null
    kill "$PID" 2>/dev/null

    COUNT=0
    while pid_is_running "$PID" && [ "$COUNT" -lt 5 ]; do
      sleep 1
      COUNT=$((COUNT + 1))
    done

    if pid_is_running "$PID"; then
      kill -9 "$PID" 2>/dev/null
    fi

    log_msg "$NAME stopped."
  else
    log_msg "Found a stale PID file for $NAME. Removed."
  fi
}

stop_web() {
  stop_pid_file "RClone Web GUI" "$RCLONEWEB_PID"
}

stop_sync() {
  stop_pid_file "RClone Sync Service" "$RCLONESYNC_PID"
}

stop_mounts() {
  log_msg "Stopping rclone mounts..."

  for mp in /mnt/rclone-*; do
    [ -e "$mp" ] || continue
    umount -l "$mp" 2>/dev/null
  done

  for proc in /proc/[0-9]*; do
    PID="${proc##*/}"
    [ -r "$proc/cmdline" ] || continue

    CMDLINE="$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null)"
    case "$CMDLINE" in
      *"/vendor/bin/rclone mount "*|*" rclone mount "*)
        kill "$PID" 2>/dev/null
        ;;
    esac
  done

  sleep 2

  for proc in /proc/[0-9]*; do
    PID="${proc##*/}"
    [ -r "$proc/cmdline" ] || continue

    CMDLINE="$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null)"
    case "$CMDLINE" in
      *"/vendor/bin/rclone mount "*|*" rclone mount "*)
        kill -9 "$PID" 2>/dev/null
        ;;
    esac
  done

  log_msg "Rclone mounts stopped."
}

start_mounts() {
  log_msg "Starting rclone mounts..."

  /vendor/bin/rclone listremotes | sed 's/:$//' | while read -r remote; do
    [ -n "$remote" ] || continue
    log_msg "Mounting $remote => /mnt/rclone-$remote => /sdcard/$remote"
    /vendor/bin/rclone-mount "$remote" --daemon
  done

  log_msg "All remotes mounted."
}

start_sync() {
  rm -f "$RCLONESYNC_PID"

  if [ -f "$RCLONESYNC_CONF" ] || [ -f "$RCLONECOPY_CONF" ]; then
    nice -n 19 ionice -c3 "$MODPATH/sync.service.sh" &
    echo "$!" > "$RCLONESYNC_PID"
    log_msg "Sync service started, PID: $(cat "$RCLONESYNC_PID")"
  else
    log_msg "No sync/copy config found. Skip sync service."
  fi
}

start_web() {
  case "$RCLONE_RC_ADDR" in
    :*)
      LOCAL_IP="$(ip route get 1 2>/dev/null | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')"
      URL="http://${LOCAL_IP:-localhost}${RCLONE_RC_ADDR}"
      ;;
    *)
      URL="$RCLONE_RC_ADDR"
      ;;
  esac

  log_msg "RClone Web GUI will start at: ${URL}"
  nohup rclone-web > "$RCLONE_LOG_DIR/rclone-web.log" 2>&1 &
  PID=$!
  echo "$PID" > "$RCLONEWEB_PID"
  log_msg "RClone Web GUI started with PID($PID)."
  log_msg "浏览器访问: ${URL}"
}

show_status() {
  if [ -f "$RCLONESYNC_PID" ] && pid_is_running "$(cat "$RCLONESYNC_PID" 2>/dev/null)"; then
    log_msg "Sync service: running (PID $(cat "$RCLONESYNC_PID"))"
  else
    log_msg "Sync service: stopped"
  fi

  if [ -f "$RCLONEWEB_PID" ] && pid_is_running "$(cat "$RCLONEWEB_PID" 2>/dev/null)"; then
    log_msg "Web GUI: running (PID $(cat "$RCLONEWEB_PID"))"
  else
    log_msg "Web GUI: stopped"
  fi

  MOUNT_COUNT="$(mount | grep -c '/mnt/rclone-' 2>/dev/null)"
  log_msg "Mounted remotes: $MOUNT_COUNT"
}

start_stack() {
  start_mounts
  start_sync
  start_web
}

stop_stack() {
  stop_web
  stop_sync
  stop_mounts
}

load_env

ACTION="${1:-restart}"

case "$ACTION" in
  start)
    start_stack
    ;;
  stop)
    stop_stack
    ;;
  restart)
    stop_stack
    sleep 2
    start_stack
    ;;
  status)
    show_status
    ;;
  web)
    stop_web
    start_web
    ;;
  *)
    log_msg "Usage: $0 [start|stop|restart|status|web]"
    exit 1
    ;;
esac
