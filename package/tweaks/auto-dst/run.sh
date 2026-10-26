#!/system/bin/sh
# auto-dst: follows daylight saving time automatically. The head unit's clock settings only offer a
# fixed-offset zone (persist.sys.timezone = Mobis/UTC-05:00) plus a manual "Daylight
# saving time" switch, so the clock is an hour off for half the year until someone flips
# it. This works out whether DST is in effect from the zone's base offset and a POSIX rule
# (US/Canada by default: second Sunday of March to first Sunday of November), and flips
# the head unit's own switch when it's wrong: TimePolicyService (binder com.hkmc.micom.time,
# ITimePolicyService: 3 = isDst, 4 = setDst(boolean)) creates or removes
# /data/system/user_dst and broadcasts com.hkmc.intent.action.TIMEZONE_RELOAD. The
# Settings checkbox reads Settings.System summer_time, so that is kept in step too.
# Both go through kt (tweak.conf's needs); the zone and the date need nothing.
# Rule override: DST_RULE="M3.2.0,M11.1.0" style (POSIX TZ), or "none" for no DST.
DST_RULE=${DST_RULE:-M3.2.0,M11.1.0}
CHECK=${CHECK:-60}

log() { echo "$(date) $1"; }

# "Mobis/UTC-05:00" -> 5 (POSIX offsets count hours west of UTC); only the head unit's fixed zones
base_offset() {
    z=$(getprop persist.sys.timezone)
    case "$z" in
        Mobis/UTC-*) sign= ; z=${z#Mobis/UTC-} ;;
        Mobis/UTC+*) sign=- ; z=${z#Mobis/UTC+} ;;
        *) return ;;
    esac
    h=${z%%:*}
    m=${z#*:}
    h=${h#0}
    [ "$m" = 00 ] && echo "$sign${h:-0}" || echo "$sign${h:-0}:$m"
}

should_be_dst() {
    [ "$DST_RULE" = none ] && { echo 0; return; }
    off=$(base_offset)
    [ -n "$off" ] || return
    [ "$(TZ="STD${off}DST,$DST_RULE" date +%Z)" = DST ] && echo 1 || echo 0
}

# reply "Result: Parcel(00000000 00000001   '........')": no exception, then the boolean
unit_dst() {
    r=$(kt binder com.hkmc.micom.time 3)
    case "$r" in
        *"Parcel(00000000 00000001"*) echo 1 ;;
        *"Parcel(00000000 00000000"*) echo 0 ;;
    esac
}

# "run.sh check": print the state once (status.sh builds on it; handy for testing)
if [ "$1" = check ]; then
    echo "zone=$(getprop persist.sys.timezone) offset=$(base_offset) rule=$DST_RULE want=$(should_be_dst) unit=$(unit_dst)"
    exit 0
fi

log "following DST (rule $DST_RULE)"
while :; do
    want=$(should_be_dst)
    have=$(unit_dst)
    if [ -n "$want" ] && [ -n "$have" ] && [ "$want" != "$have" ]; then
        kt binder com.hkmc.micom.time 4 i32 "$want" >/dev/null
        kt setting put system summer_time "$want"
        if [ "$(unit_dst)" = "$want" ]; then
            [ "$want" = 1 ] && msg="daylight saving time started" || msg="daylight saving time ended"
            log "$msg (clock now $(date))"
        else
            log "couldn't set DST to $want"
            sleep 600
        fi
    fi
    sleep "$CHECK"
done
