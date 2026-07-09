#!/system/bin/sh

L() {
  log -t Magisk "[rclone] $1"
}

find_bin() {
  NAME="$1"
  for BIN in \
    "$MODPATH/vendor/bin/$NAME" \
    "$MODPATH/system/vendor/bin/$NAME" \
    "$MODPATH/system/bin/$NAME" \
    "/vendor/bin/$NAME" \
    "/system/bin/$NAME"
  do
    [ -x "$BIN" ] && {
      echo "$BIN"
      return 0
    }
  done
  command -v "$NAME" 2>/dev/null
}

L "service script started:"

[ -z "$MODPATH" ] && MODPATH="${0%/*}"
L "load env: $MODPATH/env"
set -a && . "$MODPATH/env" && set +a

if [ -n "$RCLONE_CONFIG_DIR" ] && [ -f "$RCLONE_CONFIG_DIR/env" ]; then
  set -a && . "$RCLONE_CONFIG_DIR/env" && set +a
fi

export RCLONEDIR="$MODPATH"
export PATH="$MODPATH/vendor/bin:$MODPATH/system/vendor/bin:$PATH"

if [ -z "$RCLONE_CONFIG" ]; then
  if [ -n "$RCLONE_CONFIG_DIR" ] && [ -f "$RCLONE_CONFIG_DIR/rclone.conf" ]; then
    export RCLONE_CONFIG="$RCLONE_CONFIG_DIR/rclone.conf"
  elif [ -f "$MODPATH/conf/rclone.conf" ]; then
    export RCLONE_CONFIG="$MODPATH/conf/rclone.conf"
  fi
fi

[ -n "$RCLONE_LOG_DIR" ] && mkdir -p "$RCLONE_LOG_DIR"

RCLONE_BIN="$(find_bin rclone)"
RCLONE_MOUNT_BIN="$(find_bin rclone-mount)"

if [ -z "$RCLONE_BIN" ] || [ -z "$RCLONE_MOUNT_BIN" ]; then
  L "rclone or rclone-mount binary not found, abort."
  exit 1
fi

sed -i 's/^description=\(.\{1,4\}| \)\?/description=/' "$RCLONEPROP"

COUNT=0
until { [ "$(getprop sys.boot_completed)" = "1" ] && [ "$(getprop init.svc.bootanim)" = "stopped" ] && [ -e "/sdcard" ]; } || [ $((COUNT++)) -ge 20 ]; do
  sleep 10
done
L "system is ready after ${COUNT}. Starting the mounting process."

"${RCLONE_BIN}" listremotes | sed 's/:$//' | while read -r remote; do
  [ -n "$remote" ] || continue
  L "mount $remote => /mnt/rclone-$remote => /sdcard/$remote"
  "${RCLONE_MOUNT_BIN}" "$remote" --daemon
done

L "all remotes mounted successfully."

sed -i 's/^description=\(.\{1,4\}| \)\?/description=🚀| /' "$RCLONEPROP"

rm -f "$RCLONESYNC_PID"
if [ -f "$RCLONESYNC_CONF" ] || [ -f "$RCLONECOPY_CONF" ]; then
  nice -n 19 ionice -c3 "$MODPATH/sync.service.sh" &
  echo $! > "$RCLONESYNC_PID"
  L "sync.service.sh started, PID: $(cat "$RCLONESYNC_PID")"
else
  L "no sync/copy config found."
fi

L "service script finished!"
