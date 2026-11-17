#!/system/bin/sh
# install-device.sh -- deploy the widget's device-side scripts.
# Run as root on the phone (e.g. `su -c 'sh install-device.sh'` after pushing).
#
# What it does:
#   1. Backs up and NEUTRALISES the legacy always-on boot script, so it no
#      longer force-starts a daemon that ignores the flag.
#   2. Installs v2 daemon + unified control script into /data/adb/.
#   3. Creates the flag file (default 1 = current always-on behaviour).
#   4. Restarts the daemon according to the flag.
#
# Rollback: see README.md "Rollback" section.

set -e
SRC="${1:-/sdcard/Download/adb-wifi-widget}"
ADB_DIR=/data/adb
STAMP=$(date +%Y%m%d-%H%M%S)

echo "[1/5] Backup legacy boot script"
OLD=$ADB_DIR/service.d/90_adb_wifi_keepalive.sh
[ -f "$OLD" ] && cp -a "$OLD" "$ADB_DIR/service.d/90_adb_wifi_keepalive.sh.bak-$STAMP" || true

echo "[2/5] Neutralise legacy boot script (replace with flag-aware launcher)"
cat > "$OLD" <<'EOF'
#!/system/bin/sh
# Flag-aware launcher. Only starts the v2 daemon when flag != 0.
FLAG=/data/adb/.adb_wifi_enabled
PIDFILE=/data/adb/.adb_wifi_daemon_v2.pid
if [ -f "$FLAG" ]; then
    f=$(tr -d '\r' < "$FLAG" 2>/dev/null)
    [ "$f" = "0" ] && exit 0
fi
if [ -f "$PIDFILE" ]; then
    oldpid=$(tr -d '\r' < "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && [ -d "/proc/$oldpid" ]; then
        cmdline=$(tr '\0' ' ' < "/proc/$oldpid/cmdline" 2>/dev/null)
        case "$cmdline" in *adb_wifi_daemon_v2*) exit 0 ;; esac
    fi
fi
nohup /data/adb/adb_wifi_daemon_v2.sh >/dev/null 2>&1 </dev/null &
EOF
chmod 755 "$OLD"

echo "[3/5] Install v2 daemon + control script"
cp "$SRC/adb_wifi_daemon_v2.sh" "$ADB_DIR/adb_wifi_daemon_v2.sh"
cp "$SRC/adb_wifi_ctl.sh" "$ADB_DIR/adb_wifi_ctl.sh"
chmod 755 "$ADB_DIR/adb_wifi_daemon_v2.sh" "$ADB_DIR/adb_wifi_ctl.sh"

echo "[4/5] Ensure flag file (default 1)"
[ -f "$ADB_DIR/.adb_wifi_enabled" ] || echo 1 > "$ADB_DIR/.adb_wifi_enabled"
chmod 600 "$ADB_DIR/.adb_wifi_enabled"

echo "[5/5] Restart daemon according to flag"
$ADB_DIR/adb_wifi_ctl.sh off >/dev/null 2>&1 || true
sleep 1
$ADB_DIR/adb_wifi_ctl.sh on >/dev/null 2>&1 || true

echo "Done. Current status:"
$ADB_DIR/adb_wifi_ctl.sh status
