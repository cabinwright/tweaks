#!/system/bin/sh
# coldstart-heat: once per head unit start, if it's colder outside than THRESHOLD_F, turns on the
# heated wheel and the driver's seat through the binder services the stock controls use. Adapted
# from hkmc-coldstart-heat (eclipseempire, MIT), which found the calls on an Ioniq 5.
# The outside temperature is in the climate service's dump and nowhere a tweak can read without
# one: mAmbientTempF, or mAmbientTempC on a car set to Celsius. The raw signal beside it is 0xff
# for the unit not in use and 0x00 before the first reading, either of which the decoded value
# doesn't show.
THRESHOLD_F=50
WAIT=${COLDSTART_WAIT:-120}

log() { echo "$(date) $1"; }
last() { echo "$1" > "$TWEAK_DATA/last"; }
idle() { while :; do sleep 3600; done; }

in_range() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
whole() { case "$1" in ""|-|*[!0-9-]*|?*-*) return 1 ;; esac; }

# "<name> : 0x52" -> 52
raw() {
    local v=${DUMP#*"$1 : 0x"}
    [ "$v" != "$DUMP" ] && echo "${v%%[!0-9a-fA-F]*}"
}

# "  m<name>: 42.0" -> 42
decoded() {
    local v=${DUMP#*"m$1: "}
    [ "$v" != "$DUMP" ] || return
    v=${v%%[!0-9.-]*}
    echo "${v%%.*}"
}

valid() { case "$(raw "$1")" in ""|ff|FF|00) return 1 ;; esac; }

# sets TEMP_F, or returns 1 with no reading yet
outside_f() {
    local v
    DUMP=$(kt dump com.hkmc.micom.datc 2>/dev/null)
    if valid AmbientTempF; then
        v=$(decoded AmbientTempF)
        whole "$v" && in_range "$v" -39 140 || return 1
        TEMP_F=$v
    elif valid AmbientTempC; then
        v=$(decoded AmbientTempC)
        whole "$v" && in_range "$v" -39 60 || return 1
        TEMP_F=$((v * 9 / 5 + 32))
    else
        return 1
    fi
}

call() {   # <what> <service> <code> <value>
    local r
    r=$(kt binder "$2" "$3" i32 "$4" 2>&1)
    case "$r" in
        *"Parcel(00000000"*) log "$1: sent" ;;
        *) log "$1: refused: $r"; FAILED="$FAILED $1" ;;
    esac
}

# once per start: the runner restarting isn't a cold start
BOOT=$(cat /proc/sys/kernel/random/boot_id)
if [ "$(cat "$TWEAK_DATA/boot" 2>/dev/null)" = "$BOOT" ]; then idle; fi
echo "$BOOT" > "$TWEAK_DATA/boot"
i=0 TEMP_F=
while [ $i -lt "$WAIT" ]; do
    outside_f && break
    sleep 3; i=$((i + 3))
done
if [ -z "$TEMP_F" ]; then log "no outside temperature in ${WAIT}s"; last "no reading"; idle; fi
log "outside ${TEMP_F}F, threshold ${THRESHOLD_F}F"
if [ "$TEMP_F" -ge "$THRESHOLD_F" ]; then last "warm"; idle; fi
FAILED=
call "steering wheel" com.hkmc.vr 16 1
call "driver's seat" com.hkmc.micom.usm 213 8
if [ -n "$FAILED" ]; then last "failed$FAILED"; else last "heated"; fi
idle
