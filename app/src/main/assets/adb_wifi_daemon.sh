#!/system/bin/sh
# adb_wifi_daemon.sh -- runtime keepalive for wireless ADB. Runs as root.
# NO boot autostart. Started only by adb_wifi_ctl.sh "on".
#
# Uninstall safety: the script lives in the app's private files dir. When the
# APK is uninstalled (adb OR via Settings/launcher), Android deletes that dir.
# This daemon detects its own file is gone and exits, so it stops pinning the
# setting and leaves no running process behind.

BASE=/data/data/com.adbwifitoggle/files
SELF=$BASE/adb_wifi_daemon.sh
FLAG=$BASE/.adb_wifi_enabled
LOG=$BASE/adb_wifi_keepalive.log

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

until [ "$(getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 5; done

log "daemon started, pid=$$"

while true; do
    # Uninstall detection: our own file vanished -> app removed -> exit.
    [ -f "$SELF" ] || { log "app files dir gone (uninstall), exiting"; exit 0; }
    [ -f "$FLAG" ] || { log "flag gone, exiting"; exit 0; }

    flag=$(tr -d '\r' < "$FLAG" 2>/dev/null)
    [ "$flag" = "1" ] || { log "flag=0, exiting"; exit 0; }

    wifi=$(settings get global wifi_on 2>/dev/null | tr -d '\r')
    adbw=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r')
    if [ "$wifi" = "1" ] && [ "$adbw" != "1" ]; then
        settings put global adb_wifi_enabled 1 2>/dev/null
        log "restored adb_wifi_enabled: $adbw -> 1"
    fi
    sleep 30
done
