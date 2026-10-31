#!/system/bin/sh
# coldstart-heat: once per head unit start, if it's colder outside than the threshold, turns on the
# heated wheel and seats through the same binder services the stock controls use. Adapted from
# hkmc-coldstart-heat (eclipseempire, MIT), which found the calls and values on an Ioniq 5.
# Transaction codes differ between builds and a wrong one can do something else entirely, so
# they come by method name from this car's own framework (tweakpatch txn). A method it doesn't
# have is skipped. Settings come from the Car Controls app; without it, the defaults below.
# The outside temperature is read from logcat: the telematics ECO JSON's "outTemperature" (always
# Celsius), else the dashboard's, which is in the dashboard's unit (ui_temp_is_c).
# KT_TEST_ROOT runs it against a mock (host tests only).
R=${KT_TEST_ROOT:-}
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -n "$R" ] && PATH=$KT_TEST_PATH:$PATH
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
export ANDROID_ROOT=/system ANDROID_ASSETS=/system/app
export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
D=${0%/*}
KP=$D/../../lib/tweakpatch.jar
URI=content://dev.cabinwright.vehicle.settings/coldstart
STATE=$R/data/nemesis/cabinwright/tweaks/coldstart-heat
WORK=$STATE/work
WAIT=${COLDSTART_WAIT:-120}

threshold_f=50 wheel=1 seat_drv=0 seat_pass=0 ui_temp_is_c=0

log() { echo "$(date) $1"; }
last() { echo "$1" > "$STATE/last"; }
idle() { while :; do sleep 3600; done; }
boot_id() { cat /proc/sys/kernel/random/boot_id; }

# "Row: 0 key=wheel, value=1" -> wheel=1; only the settings above, only whole numbers
read_settings() {
    local l k v
    content query --uri $URI 2>/dev/null > "$STATE/settings"
    while IFS= read -r l; do
        case "$l" in "Row: "*) ;; *) continue ;; esac
        k=${l#*key=}; k=${k%%,*}
        v=${l#*value=}; v=${v%%,*}
        case "$v" in ""|*[!0-9]*) continue ;; esac
        case "$k" in threshold_f|wheel|seat_drv|seat_pass|ui_temp_is_c) eval "$k=$v" ;; esac
    done < "$STATE/settings"
    rm -f "$STATE/settings"
}

# the root here can't write /data/dalvik-cache, so the tool gets its own
txn() {
    if [ -n "$KT_TEST_KP" ]; then $KT_TEST_KP txn "$1" "$2"; return; fi
    ANDROID_DATA=$WORK CLASSPATH=$KP app_process /system/bin dev.cabinwright.tweaks.patch.Main txn "$1" "$2" 2>/dev/null
}

# the newest line of logcat with $1 in it
newest() {
    local l x=
    logcat -d 2>/dev/null | grep "$1" > "$STATE/log"
    while IFS= read -r l; do [ -n "$l" ] && x=$l; done < "$STATE/log"
    rm -f "$STATE/log"
    echo "$x"
}

in_range() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
whole() { case "$1" in ""|-|*[!0-9-]*|?*-*) return 1 ;; esac; }

# sets TEMP_F, or returns 1 with no reading yet
outside_f() {
    local l v
    l=$(newest '"outTemperature":')
    v=${l#*\"outTemperature\":}; v=${v%%[!0-9-]*}
    if [ -n "$l" ] && whole "$v" && in_range "$v" -50 60; then TEMP_F=$((v * 9 / 5 + 32)); return 0; fi
    l=$(newest 'setOutsideTempUIAdvanced::temp =')
    [ -n "$l" ] || return 1
    v=${l#*temp = }; v=${v%% *}; v=${v%%.*}
    whole "$v" || return 1
    if [ "$ui_temp_is_c" = 1 ]; then
        in_range "$v" -50 60 || return 1
        TEMP_F=$((v * 9 / 5 + 32))
    else
        in_range "$v" -58 140 || return 1
        TEMP_F=$v
    fi
}

call() {   # <what> <service> <method> <value>
    local c r
    c=$(txn "$2" "$3")
    case "$c" in ""|*[!0-9]*) log "$1: this car has no $3"; MISSING="$MISSING $1"; return ;; esac
    r=$(service call "$2" "$c" i32 "$4" 2>&1)
    case "$r" in
        *"Parcel(00000000"*) log "$1: sent" ;;
        *) log "$1: refused: $r"; MISSING="$MISSING $1" ;;
    esac
}

seat_step() { case "$1" in 1) echo 6 ;; 2) echo 7 ;; 3) echo 8 ;; esac; }

mkdir -p "$WORK/dalvik-cache" || exit 1
# once per start: turning the switch on, or tweaksd restarting, isn't a cold start
if [ "$(cat "$STATE/boot" 2>/dev/null)" = "$(boot_id)" ]; then idle; fi
boot_id > "$STATE/boot"
log "waiting for the car's services"
i=0
while [ $i -lt "$WAIT" ]; do
    service check com.hkmc.vr 2>/dev/null | grep -q ': found' && break
    sleep 2; i=$((i + 2))
done
read_settings
i=0 TEMP_F=
while [ $i -lt "$WAIT" ]; do
    outside_f && break
    sleep 3; i=$((i + 3))
done
if [ -z "$TEMP_F" ]; then log "no outside temperature in ${WAIT}s"; last "no reading"; idle; fi
log "outside ${TEMP_F}F, threshold ${threshold_f}F"
if [ "$TEMP_F" -ge "$threshold_f" ]; then last "warm"; idle; fi
MISSING=
[ "$wheel" = 1 ] && call wheel com.hkmc.vr set_StrgWhlHeated_Cmd_AVN 1
s=$(seat_step "$seat_drv")
[ -n "$s" ] && call driver com.hkmc.micom.usm setFrontSeatHeatDrvStep "$s"
s=$(seat_step "$seat_pass")
[ -n "$s" ] && call passenger com.hkmc.micom.usm setFrontSeatHeatAstStep "$s"
if [ -n "$MISSING" ]; then last "failed$MISSING"; else last "heated"; fi
log "done"
idle
