#!/system/bin/sh
# adb_wifi_ctl.sh -- unified control for wireless ADB + keepalive daemon.
# Runs as root (invoked via Magisk su from the widget app, or from shell).
#
# Usage:  adb_wifi_ctl.sh on | off | toggle | status
#
# Design notes:
#   - A flag file (/data/adb/.adb_wifi_enabled) is the single source of truth.
#     The boot script and daemon both read it, so "off" survives reboot and
#     the daemon will not resurrect a disabled state.
#   - "off" also kills the legacy daemon (adb_wifi_daemon.sh) so it cannot
#     flip adb_wifi_enabled back to 1 every 30s.

FLAG=/data/adb/.adb_wifi_enabled
DAEMON=/data/adb/adb_wifi_daemon_v2.sh
PIDFILE=/data/adb/.adb_wifi_daemon_v2.pid
OLD_PIDFILE=/data/adb/.adb_wifi_daemon.pid

ACTION="$1"

read_flag() {
    if [ -f "$FLAG" ]; then
        tr -d '\r' < "$FLAG" 2>/dev/null
    else
        echo "1"   # default: keep current behaviour (always on)
    fi
}

write_flag() {
    echo "$1" > "$FLAG" 2>/dev/null
    chmod 600 "$FLAG" 2>/dev/null
}

is_running() {
    pf="$1"
    match="$2"
    [ -f "$pf" ] || return 1
    p=$(tr -d '\r' < "$pf" 2>/dev/null)
    [ -n "$p" ] || return 1
    [ -d "/proc/$p" ] || return 1
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    case "$cmd" in
        *"$match"*) return 0 ;;
        *) return 1 ;;
    esac
}

start_daemon() {
    if is_running "$PIDFILE" "adb_wifi_daemon_v2"; then
        return 0
    fi
    nohup "$DAEMON" >/dev/null 2>&1 </dev/null &
}

stop_daemon() {
    if is_running "$PIDFILE" "adb_wifi_daemon_v2"; then
        p=$(tr -d '\r' < "$PIDFILE" 2>/dev/null)
        kill "$p" 2>/dev/null
    fi
    rm -f "$PIDFILE" 2>/dev/null
    # Legacy daemon from the previous always-on setup.
    if is_running "$OLD_PIDFILE" "adb_wifi_daemon"; then
        p=$(tr -d '\r' < "$OLD_PIDFILE" 2>/dev/null)
        kill "$p" 2>/dev/null
    fi
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
    echo "wireless adb: OFF"
}

do_status() {
    en=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r')
    fl=$(read_flag)
    dmn=0
    is_running "$PIDFILE" "adb_wifi_daemon_v2" && dmn=1
    is_running "$OLD_PIDFILE" "adb_wifi_daemon" && dmn=1

    ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    # ss -tlnp line looks like: LISTEN 0 4 *:38983 *:* users:(("adbd",pid=..))
    # Pull the local port from the "*:PORT" field.
    port=$(ss -tlnp 2>/dev/null | grep adbd | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^\*:([0-9]+)$/){sub(/^\*:/,"",$i); print $i; exit}}')

    ssid=$(cmd wifi status 2>/dev/null | grep -i 'SSID:' | head -1 | sed 's/.*SSID:[[:space:]]*//' | tr -d '"')
    [ -n "$ssid" ] || ssid=$(dumpsys wifi 2>/dev/null | grep -oE 'ssid: [^ ]+' | tail -1 | cut -d' ' -f2 | tr -d '"')

    host=$(tail -1 /data/misc/adb/adb_keys 2>/dev/null | awk '{print $2}')

    echo "enabled=$en"
    echo "flag=$fl"
    echo "daemon=$dmn"
    echo "ip=${ip:---}"
    echo "port=${port:---}"
    echo "ssid=${ssid:---}"
    echo "host=${host:---}"
}

case "$ACTION" in
    on)     do_on ;;
    off)    do_off ;;
    toggle)
        if [ "$(read_flag)" = "0" ]; then do_on; else do_off; fi
        ;;
    status) do_status ;;
    *)
        echo "usage: $0 {on|off|toggle|status}" >&2
        exit 2
        ;;
esac
