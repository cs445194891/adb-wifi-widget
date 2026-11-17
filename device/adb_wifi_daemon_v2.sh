#!/system/bin/sh
# adb_wifi_daemon_v2.sh -- flag-aware keepalive for wireless ADB.
# Replaces the always-on adb_wifi_daemon.sh. Runs as root.
#
# Difference from v1: honours /data/adb/.adb_wifi_enabled.
#   flag=1 -> keep adb_wifi_enabled pinned to 1 while Wi-Fi is on
#   flag=0 -> exit immediately (so "off" survives reboot: boot script
#             still launches this, but it quits because flag is 0)

FLAG=/data/adb/.adb_wifi_enabled
PIDFILE=/data/adb/.adb_wifi_daemon_v2.pid
LOG=/data/adb/adb_wifi_keepalive.log

echo $$ > "$PIDFILE" 2>/dev/null

log() {
    echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null
}

read_flag() {
    if [ -f "$FLAG" ]; then
        tr -d '\r' < "$FLAG" 2>/dev/null
    else
        echo "1"
    fi
}

# Do not fight the framework during early boot.
until [ "$(getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 5
done

if [ "$(read_flag)" != "1" ]; then
    log "v2 daemon started but flag=0, exiting"
    rm -f "$PIDFILE" 2>/dev/null
    exit 0
fi

log "v2 daemon started, pid=$$"

while true; do
    if [ "$(read_flag)" != "1" ]; then
        log "flag flipped to 0, daemon exiting"
        rm -f "$PIDFILE" 2>/dev/null
        exit 0
    fi

    wifi=$(settings get global wifi_on 2>/dev/null | tr -d '\r')
    adbw=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r')

    if [ "$wifi" = "1" ] && [ "$adbw" != "1" ]; then
        settings put global adb_wifi_enabled 1 2>/dev/null
        log "restored adb_wifi_enabled: $adbw -> 1"
    fi

    sleep 30
done
