#!/system/bin/sh

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

RCLONE_BIN="$(find_bin rclone)"
if [ -z "$RCLONE_BIN" ]; then
  echo "Error: rclone binary not found." >> "$RCLONE_LOG_DIR/rclone_sync.log"
  exit 1
fi

SYNC_LOG="$RCLONE_LOG_DIR/rclone_sync.log"
COPY_LOG="$RCLONE_LOG_DIR/rclone_copy.log"
TASK_COUNT=0

cleanup() {
  rm -f "$RCLONESYNC_PID"
}

trap cleanup EXIT INT TERM

echo "$$" > "$RCLONESYNC_PID"

run_job_file() {
  MODE="$1"
  CONF_FILE="$2"
  LOG_FILE="$3"

  [ -f "$CONF_FILE" ] || return 0

  unset RCLONE_RC

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*)
        continue
        ;;
    esac

    if eval "set -- $line"; then
      nice -n 19 ionice -c3 "$RCLONE_BIN" "$MODE" "$@" >> "$LOG_FILE" 2>&1
      if [ $? -ne 0 ]; then
        echo "Error: rclone $MODE failed for arguments: $line" >> "$LOG_FILE"
      fi
      TASK_COUNT=$((TASK_COUNT + 1))
    else
      echo "Error: failed to parse $MODE arguments: $line" >> "$LOG_FILE"
    fi
  done < "$CONF_FILE"
}

sync_all() {
  TASK_COUNT=0
  run_job_file sync "$RCLONESYNC_CONF" "$SYNC_LOG"
  run_job_file copy "$RCLONECOPY_CONF" "$COPY_LOG"
}

rm -f "$SYNC_LOG" "$COPY_LOG"

while [ -f "$RCLONESYNC_PID" ]; do
  sync_all

  if [ "$TASK_COUNT" -eq 0 ]; then
    echo "No sync or copy tasks found in configuration files." >> "$SYNC_LOG"
    rm -f "$RCLONESYNC_PID"
    break
  fi

  sleep 180
done
