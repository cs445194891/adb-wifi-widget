#!/system/bin/sh
# adb_wifi_ctl.sh -- control developer mode / USB debugging / wireless ADB.
# Installed by the app into its own private files dir, runs as root via Magisk su.
# Usage:
#   adb_wifi_ctl.sh dev_on|dev_off|dev_toggle
#   adb_wifi_ctl.sh usb_on|usb_off|usb_toggle
#   adb_wifi_ctl.sh wifi_on|wifi_off|wifi_toggle
#   adb_wifi_ctl.sh status
#
# Master semantics (dev switch):
#   dev_off = development_settings_enabled=0, adb_enabled=0,
#             adb_wifi_enabled=0, keepalive daemon stopped.
#   dev_on  = development_settings_enabled=1, adb_enabled=1,
#             adb_wifi_enabled=0, keepalive daemon stopped.
# wifi_on/off keep the existing behaviour: pin adb_wifi_enabled and
# start/stop the runtime daemon. The daemon itself is unchanged.
#
# NO boot autostart. Uninstall-safe: scripts live in the app private dir.

BASE=/data/data/com.adbwifitoggle/files
FLAG=$BASE/.adb_wifi_enabled
DAEMON=$BASE/adb_wifi_daemon.sh
PIDFILE=$BASE/adb_wifi_daemon.pid

read_flag() {
    if [ -f "$FLAG" ]; then tr -d '\r' < "$FLAG" 2>/dev/null; else echo 1; fi
}
write_flag() {
    echo "$1" > "$FLAG" 2>/dev/null
    chmod 600 "$FLAG" 2>/dev/null
}
daemon_running() {
    p=$(cat "$PIDFILE" 2>/dev/null | tr -d '\r')
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        return 0
    fi
    ps -A -o ARGS 2>/dev/null | grep -q '[a]db_wifi_daemon.sh'
}
start_daemon() {
    daemon_running && return 0
    rm -f "$PIDFILE" 2>/dev/null
    nohup "$DAEMON" >/dev/null 2>&1 </dev/null &
    sleep 0.3 2>/dev/null || true
}
stop_daemon() {
    p=$(cat "$PIDFILE" 2>/dev/null | tr -d '\r')
    if [ -n "$p" ]; then
        kill "$p" 2>/dev/null
        i=0
        while kill -0 "$p" 2>/dev/null && [ $i -lt 10 ]; do
            sleep 0.1 2>/dev/null || true
            i=$((i+1))
        done
        kill -9 "$p" 2>/dev/null
    fi
    for q in $(ps -A 2>/dev/null | grep '[a]db_wifi_daemon.sh' | awk '{print $2}'); do
        kill "$q" 2>/dev/null
    done
    for q in $(ps -A -o PID,ARGS 2>/dev/null | grep '[a]db_wifi_daemon.sh' | awk '{print $1}'); do
        kill "$q" 2>/dev/null
    done
    sleep 0.3 2>/dev/null || true
    rm -f "$PIDFILE" 2>/dev/null
}

# --- developer mode (master) -------------------------------------------------
do_dev_on() {
    settings put global development_settings_enabled 1 2>/dev/null
    settings put global adb_enabled 1 2>/dev/null
    settings put global adb_wifi_enabled 0 2>/dev/null
    write_flag 0
    stop_daemon
    echo "developer mode: ON (usb=on, wifi=off, daemon=stopped)"
}
do_dev_off() {
    settings put global development_settings_enabled 0 2>/dev/null
    settings put global adb_enabled 0 2>/dev/null
    settings put global adb_wifi_enabled 0 2>/dev/null
    write_flag 0
    stop_daemon
    sleep 0.3 2>/dev/null || true
    echo "developer mode: OFF (usb=off, wifi=off, daemon=stopped)"
}
dev_toggle() {
    v=$(settings get global development_settings_enabled 2>/dev/null | tr -d '\r')
    [ "$v" = "1" ] && do_dev_off || do_dev_on
}

# --- USB debugging -----------------------------------------------------------
do_usb_on() {
    settings put global adb_enabled 1 2>/dev/null
    echo "usb debugging: ON"
}
do_usb_off() {
    settings put global adb_enabled 0 2>/dev/null
    echo "usb debugging: OFF"
}
usb_toggle() {
    v=$(settings get global adb_enabled 2>/dev/null | tr -d '\r')
    [ "$v" = "1" ] && do_usb_off || do_usb_on
}

# --- wireless ADB ------------------------------------------------------------
do_wifi_on() {
    write_flag 1
    settings put global adb_wifi_enabled 1 2>/dev/null
    start_daemon
    echo "wireless adb: ON"
}
do_wifi_off() {
    write_flag 0
    settings put global adb_wifi_enabled 0 2>/dev/null
    stop_daemon
    sleep 0.3 2>/dev/null || true
    echo "wireless adb: OFF"
}
wifi_toggle() {
    [ "$(read_flag)" = "0" ] && do_wifi_on || do_wifi_off
}

# --- status ------------------------------------------------------------------
do_status() {
    dev=$(settings get global development_settings_enabled 2>/dev/null | tr -d '\r')
    usb=$(settings get global adb_enabled 2>/dev/null | tr -d '\r')
    en=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r')
    fl=$(read_flag)
    dmn=0; daemon_running && dmn=1
    ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    port=$(ss -tlnp 2>/dev/null | grep adbd | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^\*:([0-9]+)$/){sub(/^\*:/,"",$i); print $i; exit}}')
    ssid=$(cmd wifi status 2>/dev/null | grep -o 'SSID: "[^"]*"' | head -1 | sed 's/^SSID: "//; s/"$//')
    [ -n "$ssid" ] || ssid=$(dumpsys wifi 2>/dev/null | grep -oE 'ssid: [^ ]+' | tail -1 | cut -d' ' -f2 | tr -d '"')
    echo "devmode=${dev:---}"
    echo "usb=${usb:---}"
    echo "enabled=${en:---}"
    echo "flag=$fl"
    echo "daemon=$dmn"
    echo "ip=${ip:---}"
    echo "port=${port:---}"
    echo "ssid=${ssid:---}"
}

case "$1" in
    dev_on)      do_dev_on ;;
    dev_off)     do_dev_off ;;
    dev_toggle)  dev_toggle ;;
    usb_on)      do_usb_on ;;
    usb_off)     do_usb_off ;;
    usb_toggle)  usb_toggle ;;
    wifi_on)     do_wifi_on ;;
    wifi_off)    do_wifi_off ;;
    wifi_toggle) wifi_toggle ;;
    status)      do_status ;;
    *) echo "usage: $0 {dev_on|dev_off|dev_toggle|usb_on|usb_off|usb_toggle|wifi_on|wifi_off|wifi_toggle|status}" >&2; exit 2 ;;
esac
