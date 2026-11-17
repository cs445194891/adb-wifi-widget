#!/system/bin/sh
# adb_wifi_ctl.sh -- control wireless ADB + runtime keepalive.
# Installed by the app into its own private files dir, runs as root via Magisk su.
# Usage: adb_wifi_ctl.sh on | off | toggle | status
#
# NO boot autostart: the daemon is started only by "on" and exits when the
# app's private files dir is removed (i.e. the APK was uninstalled).

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
    # Legacy fallback: daemons started before the pidfile existed.
    ps -A -o ARGS 2>/dev/null | grep -q '[a]db_wifi_daemon.sh'
}
start_daemon() {
    daemon_running && return 0
    rm -f "$PIDFILE" 2>/dev/null
    nohup "$DAEMON" >/dev/null 2>&1 </dev/null &
    # Give the daemon a moment to write its pidfile.
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
    # Fallback for stray/legacy daemons. Try both common ps layouts.
    for q in $(ps -A 2>/dev/null | grep '[a]db_wifi_daemon.sh' | awk '{print $2}'); do
        kill "$q" 2>/dev/null
    done
    for q in $(ps -A -o PID,ARGS 2>/dev/null | grep '[a]db_wifi_daemon.sh' | awk '{print $1}'); do
        kill "$q" 2>/dev/null
    done
    sleep 0.3 2>/dev/null || true
    rm -f "$PIDFILE" 2>/dev/null
}

do_on() {
    write_flag 1
    settings put global adb_wifi_enabled 1 2>/dev/null
    start_daemon
    echo "wireless adb: ON"
}
do_off() {
    write_flag 0
    settings put global adb_wifi_enabled 0 2>/dev/null
    stop_daemon
    # Let the process exit and the pidfile vanish before callers read status.
    sleep 0.3 2>/dev/null || true
    echo "wireless adb: OFF"
}
do_status() {
    en=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r')
    fl=$(read_flag)
    dmn=0; daemon_running && dmn=1
    ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    port=$(ss -tlnp 2>/dev/null | grep adbd | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^\*:([0-9]+)$/){sub(/^\*:/,"",$i); print $i; exit}}')
    ssid=$(cmd wifi status 2>/dev/null | grep -o 'SSID: "[^"]*"' | head -1 | sed 's/^SSID: "//; s/"$//')
    [ -n "$ssid" ] || ssid=$(dumpsys wifi 2>/dev/null | grep -oE 'ssid: [^ ]+' | tail -1 | cut -d' ' -f2 | tr -d '"')
    echo "enabled=$en"
    echo "flag=$fl"
    echo "daemon=$dmn"
    echo "ip=${ip:---}"
    echo "port=${port:---}"
    echo "ssid=${ssid:---}"
}

case "$1" in
    on)     do_on ;;
    off)    do_off ;;
    toggle) [ "$(read_flag)" = "0" ] && do_on || do_off ;;
    status) do_status ;;
    *) echo "usage: $0 {on|off|toggle|status}" >&2; exit 2 ;;
esac
