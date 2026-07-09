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
    if [ -x "$BIN" ]; then
      echo "$BIN"
      return 0
    fi
  done

  command -v "$NAME" 2>/dev/null
}

L "service script started:"

[ "${MODPATH}"x = ""x ] && MODPATH="${0%/*}"
L "load env: $MODPATH/env"
set -a && . "$MODPATH/env" && set +a

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

"$RCLONE_BIN" listremotes | sed 's/:$//' | while read -r remote; do
  [ -n "$remote" ] || continue
  L "mount $remote => /mnt/rclone-$remote => /sdcard/$remote"
  "$RCLONE_MOUNT_BIN" "$remote" --daemon
done

L "all remotes mounted successfully."

sed -i 's/^description=\(.\{1,4\}| \)\?/description=🚀| /' "$RCLONEPROP"

rm -f "$RCLONESYNC_PID"
nice -n 19 ionice -c3 "$MODPATH/sync.service.sh" &
echo $! > "$RCLONESYNC_PID"
L "sync.service.sh started, PID: $(cat "$RCLONESYNC_PID")"

L "service script finished!"
