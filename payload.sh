#!/bin/sh
# Title: GS Drone Detector
# Author: GhostStrats
# Description: Passive one-second Wi-Fi candidate tracker with RSSI meter and Pager alerts
# Category: Reconnaissance
# Receives Wi-Fi beacons only. Names are not verified drones and RSSI is not distance.

# Monitor mode: capture for one second, then immediately sample the next window.
# Managed Wi-Fi scans can take longer, depending on the radio/driver.
WINDOW=${GS_SCAN_WINDOW:-1}
MAX_ROUNDS=${GS_MAX_ROUNDS:-0}
DEMO=${GS_DEMO:-0}
FORCE_IFACE=${GS_WIFI_IFACE:-}
SOUND=${GS_SOUND:-1}
VIBRATION=${GS_VIBRATE:-1}
CLOSE_REPEAT=${GS_CLOSE_REPEAT:-25}
BAR_WIDTH=10
MEDIUM=-75
STRONG=-60
CLOSE=-45

case "$WINDOW" in ''|*[!0-9]*) WINDOW=1;; esac
[ "$WINDOW" -ge 1 ] || WINDOW=1
[ "$WINDOW" -le 10 ] || WINDOW=10
case "$MAX_ROUNDS" in ''|*[!0-9]*) MAX_ROUNDS=0;; esac
case "$CLOSE_REPEAT" in ''|*[!0-9]*) CLOSE_REPEAT=25;; esac
[ "$CLOSE_REPEAT" -ge 10 ] || CLOSE_REPEAT=10

TMP="${TMPDIR:-/tmp}/gsdrone.$$"
cleanup() { rm -f "$TMP.interfaces" "$TMP.iw" "$TMP.capture" "$TMP.parsed" "$TMP.candidates" "$TMP.err"; }
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

log() {
    level=$1; shift
    if command -v LOG >/dev/null 2>&1; then
        LOG "$level" "$*"
    else
        printf '%s\n' "$*"
    fi
}

choose_backend() {
    BACKEND=''; IFACE=''
    if [ "$DEMO" = 1 ]; then BACKEND=demo; IFACE=demo; return 0; fi
    command -v iw >/dev/null 2>&1 || return 1
    iw dev > "$TMP.iw" 2>/dev/null || return 1
    awk '$1=="Interface"{dev=$2} $1=="type"&&dev!=""{print dev"|"$2}' "$TMP.iw" > "$TMP.interfaces"
    if [ -n "$FORCE_IFACE" ]; then
        if grep -q "^$FORCE_IFACE|monitor$" "$TMP.interfaces"; then
            BACKEND=monitor; IFACE=$FORCE_IFACE
        elif grep -q "^$FORCE_IFACE|managed$" "$TMP.interfaces"; then
            BACKEND=managed; IFACE=$FORCE_IFACE
        else
            return 1
        fi
        return 0
    fi
    if command -v tcpdump >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        # wlan2mon can exist as an empty USB-radio placeholder. Prefer built-in tri-band.
        for nic in wlan1mon wlan0mon wlan2mon; do
            if grep -q "^$nic|monitor$" "$TMP.interfaces"; then
                BACKEND=monitor; IFACE=$nic; return 0
            fi
        done
        nic=$(awk -F '|' '$2=="monitor"{print $1;exit}' "$TMP.interfaces")
        if [ -n "$nic" ]; then BACKEND=monitor; IFACE=$nic; return 0; fi
    fi
    # This is slower than passive monitor-mode capture; don't disrupt management AP wlan0.
    for nic in wlan1 wlan2 wlan0cli; do
        if grep -q "^$nic|managed$" "$TMP.interfaces"; then
            BACKEND=managed; IFACE=$nic; return 0
        fi
    done
    nic=$(awk -F '|' '$2=="managed"&&$1!="wlan0"{print $1;exit}' "$TMP.interfaces")
    if [ -n "$nic" ]; then BACKEND=managed; IFACE=$nic; return 0; fi
    return 1
}

parse_beacons() {
    # tcpdump -e monitor-mode beacons contain SSIDs and often radiotap -NdBm signal.
    awk '
    {
        line=$0
        if (line !~ /Beacon \(/ && line !~ /Probe Response \(/) next
        if (line ~ /Beacon \(/) sub(/^.*Beacon \(/,"",line)
        else sub(/^.*Probe Response \(/,"",line)
        sub(/\).*$/,"",line)
        if (line=="" || line=="<hidden>") next
        rssi="?"
        for (i=1;i<=NF;i++) {
            v=$i
            if (v ~ /^-[0-9]+dBm$/) { sub(/dBm$/,"",v); rssi=v; break }
            if (v ~ /^-[0-9]+$/ && (i<NF) && $(i+1) ~ /^dBm/) {rssi=v;break}
        }
        gsub(/\|/,"/",line)
        print line "|" rssi "|unknown"
    }' "$TMP.capture" > "$TMP.parsed"
}

scan_once() {
    : > "$TMP.parsed"; : > "$TMP.err"
    case "$BACKEND" in
        demo)
            # Repeatable simulated signal, including brief signal loss.
            case $((ROUND%9)) in
                1) R=-85;; 2) R=-74;; 3) R=-64;; 4) R=-56;; 5) R=-43;;
                6) R=-32;; 7) R=-47;; 8) R=-62;; 0) return 0;;
            esac
            printf 'DJI-TEST|%s|02:00:00:00:00:01\n' "$R" > "$TMP.parsed"
            return 0;;
        managed)
            # iw scan may take >1s and cache entries; never claim 1s full sweeps here.
            iw dev "$IFACE" scan > "$TMP.capture" 2> "$TMP.err" || return 1
            awk '
                /^BSS /{if(ssid!=""&&rssi!="")print ssid"|"rssi"|"mac;mac=$2;sub(/\(.*/,"",mac);ssid="";rssi=""}
                /^[[:space:]]*signal:/{rssi=int($2)}
                /^[[:space:]]*SSID:/{ssid=$0;sub(/^[[:space:]]*SSID:[[:space:]]*/, "", ssid);gsub(/\|/,"/",ssid)}
                END{if(ssid!=""&&rssi!="")print ssid"|"rssi"|"mac}
            ' "$TMP.capture" > "$TMP.parsed"
            return 0;;
        monitor)
            command -v tcpdump >/dev/null 2>&1 || return 1
            command -v timeout >/dev/null 2>&1 || return 1
            # A one-second *observation window*, not a sweep of every Wi-Fi channel.
            # SIGINT lets tcpdump flush its line-buffered output cleanly.
            timeout -s INT "$WINDOW" tcpdump -i "$IFACE" -n -e -l -s 512 \
                'type mgt subtype beacon or type mgt subtype probe-resp' \
                > "$TMP.capture" 2> "$TMP.err" || :
            if grep -Eiq 'permission denied|no such device|not found|not supported|couldn.t open|invalid interface|not permitted' "$TMP.err"; then
                return 1
            fi
            parse_beacons
            return 0;;
    esac
    return 1
}

filter_candidates() {
    # Only names that suggest drone-related Wi-Fi gear. Not proof of an aircraft.
    awk -F '|' '{s=toupper($1);if(s ~ /DJI|MAVIC|MATRICE|PHANTOM|AVATA|TELLO|SKYDIO|AUTEL|ANAFI|PARROT|HOLYSTONE|HOLY.STONE|POTENSIC|HUBSAN|BETAFPV|FIMI|EMAX|FPV|DRONE/)print}' \
        "$TMP.parsed" > "$TMP.candidates"
}

rssi_valid() {
    case "$1" in -[0-9]*|[0-9]*) return 0;; *) return 1;; esac
}

level_for() {
    if [ "$1" -ge "$CLOSE" ]; then LEVEL=CLOSE; STATUS='MAY BE CLOSE'; COLOR=red
    elif [ "$1" -ge "$STRONG" ]; then LEVEL=STRONG; STATUS='POSSIBLY NEAR'; COLOR=yellow
    elif [ "$1" -ge "$MEDIUM" ]; then LEVEL=MODERATE; STATUS='MODERATE'; COLOR=blue
    else LEVEL=WEAK; STATUS='WEAK SIGNAL'; COLOR=green
    fi
}

signal_bar() {
    rssi=$1
    filled=$(( (rssi + 95) * BAR_WIDTH / 60 ))
    [ "$filled" -lt 0 ] && filled=0
    [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
    result='['; i=0
    while [ "$i" -lt "$BAR_WIDTH" ]; do
        if [ "$i" -lt "$filled" ]; then result="${result}#"; else result="${result}-"; fi
        i=$((i+1))
    done
    BAR="${result}]"
}

alert_sound() {
    if [ "$SOUND" = 1 ]; then
        if command -v RINGTONE >/dev/null 2>&1; then
            if ! RINGTONE 'alert' >/dev/null 2>&1 && [ "$SOUND_WARNED" -eq 0 ]; then
                log yellow 'RINGTONE unavailable in this runtime'
                SOUND_WARNED=1
            fi
        elif [ "$SOUND_WARNED" -eq 0 ]; then
            log yellow 'RINGTONE command not available'
            SOUND_WARNED=1
        fi
    fi
    if [ "$VIBRATION" = 1 ] && command -v VIBRATE >/dev/null 2>&1; then
        VIBRATE >/dev/null 2>&1 || :
    fi
}

if ! choose_backend; then
    log red 'GS DRONE DETECTOR: NO SCAN INTERFACE'
    log yellow 'Check: iw dev / tcpdump / timeout'
    exit 1
fi
log blue 'GS DRONE DETECTOR | LIVE TRACKER'
log blue "Scanner: $BACKEND / $IFACE"
log yellow 'Wi-Fi name candidate, NOT verified drone'
if [ "$BACKEND" = managed ]; then
    log yellow 'Managed scans: refresh may exceed 1s'
fi

ROUND=0; FAIL=0; MISSES=0
TRACK_NAME=''; TRACK_LEVEL=''; TRACK_RSSI=''; TRACK_AVG=''
LAST_ALERT_KEY=''; LAST_ALERT=0; SOUND_WARNED=0
LAST_UPDATE_SEC=0

while :; do
    ROUND=$((ROUND+1))
    START=$(date +%s)
    if scan_once; then
        FAIL=0
        filter_candidates
        # Prefer the previously tracked SSID when still visible. Otherwise use the
        # strongest candidate rather than jumping between names every second.
        FOUND_NAME=''; FOUND_RSSI=''; BEST_NAME=''; BEST_RSSI=-999
        UNKNOWN_NAME=''; STICKY_NAME=''; STICKY_RSSI=''
        while IFS='|' read -r SSID DBM MAC; do
            [ -n "$SSID" ] || continue
            if rssi_valid "$DBM"; then
                if [ "$DBM" -gt "$BEST_RSSI" ]; then
                    BEST_RSSI=$DBM; BEST_NAME=$SSID
                fi
                if [ -n "$TRACK_NAME" ] && [ "$SSID" = "$TRACK_NAME" ]; then
                    STICKY_NAME=$SSID; STICKY_RSSI=$DBM
                fi
            else
                [ -n "$UNKNOWN_NAME" ] || UNKNOWN_NAME=$SSID
            fi
        done < "$TMP.candidates"
        if [ -n "$STICKY_NAME" ]; then
            FOUND_NAME=$STICKY_NAME; FOUND_RSSI=$STICKY_RSSI
        elif [ -n "$BEST_NAME" ]; then
            FOUND_NAME=$BEST_NAME; FOUND_RSSI=$BEST_RSSI
        elif [ -n "$UNKNOWN_NAME" ]; then
            FOUND_NAME=$UNKNOWN_NAME; FOUND_RSSI='?'
        fi
        NOW=$(date +%s)
        if [ -n "$FOUND_NAME" ]; then
            MISSES=0
            NEW=0
            if [ "$FOUND_NAME" != "$TRACK_NAME" ]; then
                NEW=1; TRACK_AVG=''
                TRACK_NAME=$FOUND_NAME; TRACK_LEVEL=''
                log yellow "TRACKING: $(printf '%s' "$TRACK_NAME" | cut -c1-29)"
            fi
            if rssi_valid "$FOUND_RSSI"; then
                # Small integer moving average prevents wildly jumping near/far labels.
                if rssi_valid "$TRACK_AVG"; then
                    TRACK_AVG=$(( (TRACK_AVG + FOUND_RSSI) / 2 ))
                else
                    TRACK_AVG=$FOUND_RSSI
                fi
                TRACK_RSSI=$FOUND_RSSI
                level_for "$TRACK_AVG"
                signal_bar "$TRACK_AVG"
                log "$COLOR" "SIG $BAR ${TRACK_AVG}dBm $STATUS"
            else
                LEVEL=UNKNOWN
                log yellow 'SIG [??????????] UNKNOWN RSSI'
            fi
            # Sound on a new name (with cooldown), an escalation into close-strength,
            # or a reminder if the close-strength signal persists.
            RING=0
            if [ "$NEW" -eq 1 ]; then
                if [ "$TRACK_NAME" != "$LAST_ALERT_KEY" ] || [ $((NOW-LAST_ALERT)) -ge 30 ]; then
                    RING=1
                fi
            elif [ "$LEVEL" = CLOSE ] && [ "$TRACK_LEVEL" != CLOSE ]; then
                if [ $((NOW-LAST_ALERT)) -ge 10 ]; then RING=1; fi
            elif [ "$LEVEL" = CLOSE ] && [ $((NOW-LAST_ALERT)) -ge "$CLOSE_REPEAT" ]; then
                RING=1
            fi
            if [ "$RING" -eq 1 ]; then
                alert_sound
                LAST_ALERT=$NOW; LAST_ALERT_KEY=$TRACK_NAME
            fi
            TRACK_LEVEL=$LEVEL
        else
            MISSES=$((MISSES+1))
            if [ -n "$TRACK_NAME" ]; then
                if [ "$MISSES" -lt 3 ]; then
                    log yellow "TRACK HOLD - no beacon ($MISSES/3)"
                else
                    log green 'SIGNAL LOST - BACK TO MONITORING'
                    TRACK_NAME=''; TRACK_AVG=''; TRACK_RSSI=''; TRACK_LEVEL=''
                fi
            elif [ "$ROUND" -eq 1 ] || [ $((ROUND%15)) -eq 0 ]; then
                log green 'MONITORING - no Wi-Fi candidates'
            fi
        fi
    else
        FAIL=$((FAIL+1))
        if [ "$FAIL" -eq 1 ]; then
            log yellow "Scan error: $BACKEND/$IFACE"
            head -n 1 "$TMP.err" 2>/dev/null | cut -c1-60 | while IFS= read -r line; do
                [ -n "$line" ] && log yellow "$line"
            done
        fi
        if [ "$FAIL" -ge 3 ]; then
            log red 'STOPPED: 3 consecutive scan failures'
            break
        fi
    fi
    if [ "$MAX_ROUNDS" -gt 0 ] && [ "$ROUND" -ge "$MAX_ROUNDS" ]; then
        log blue 'TEST COMPLETE'
        break
    fi
    # Monitor backend already spent ~1 s sampling; do not insert another 1 s.
    # Managed/demo backend gets a short pacing delay only if required.
    if [ "$BACKEND" = managed ] && [ "$(date +%s)" -eq "$START" ]; then
        sleep 1
    fi
done
