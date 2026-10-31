#!/bin/sh
# Host test: the coldstart-heat tweak against a mock head unit (stubs for logcat, content, service
# and the transaction lookup). KT_SH=mksh|bash picks the shell.
# usage: sh tests/coldstart-test.sh
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/package/tweaks/coldstart-heat
SH=${KT_SH:-sh}
W=$(mktemp -d)
PID=
trap '[ -n "$PID" ] && kill $PID 2>/dev/null; rm -rf "$W"' EXIT
fails=0
export KT_TEST_ROOT="$W/root" KT_TEST_PATH="$W/stubs:/usr/bin:/bin" COLDSTART_WAIT=4
export KT_TEST_KP="sh $W/kp"
M="$KT_TEST_ROOT"
mkdir -p "$W/stubs"
cat > "$W/stubs/logcat" <<EOF
#!/bin/sh
cat $M/logcat 2>/dev/null
EOF
cat > "$W/stubs/content" <<EOF
#!/bin/sh
cat $M/settings 2>/dev/null
EOF
cat > "$W/stubs/service" <<EOF
#!/bin/sh
[ "\$1" = check ] && { echo "Service \$2: found"; exit 0; }
shift
echo "\$*" >> $M/calls
if [ -f $M/refuse ]; then echo "Result: Parcel(ffffffb4 00000000)"; else echo "Result: Parcel(00000000    '....')"; fi
EOF
cat > "$W/stubs/sleep" <<'EOF'
#!/bin/sh
[ "$1" = 3600 ] && exec /bin/sleep 3600
exit 0
EOF
cat > "$W/stubs/cat" <<EOF
#!/bin/sh
case "\$1" in /proc/sys/kernel/random/boot_id) cat_boot=\$(/bin/cat $M/bootid); echo "\$cat_boot" ;; *) /bin/cat "\$@" ;; esac
EOF
chmod 755 "$W"/stubs/*
cat > "$W/kp" <<EOF
case "\$3" in
    set_StrgWhlHeated_Cmd_AVN) echo 16 ;;
    setFrontSeatHeatDrvStep) [ -f $M/no-seats ] || echo 213 ;;
    setFrontSeatHeatAstStep) [ -f $M/no-seats ] || echo 214 ;;
    *) exit 1 ;;
esac
EOF
fresh() { rm -rf "$M"; mkdir -p "$M"; echo boot-1 > "$M/bootid"; : > "$M/calls"; }
# runs run.sh until it idles
start() {
    $SH "$T/run.sh" > "$W/log" 2>&1 &
    PID=$!
    n=0
    while [ $n -lt 100 ] && ! grep -qE 'done|threshold|no outside' "$W/log" && [ "$1" != quiet ]; do /bin/sleep 0.1; n=$((n + 1)); done
    /bin/sleep 0.3
    pkill -P $PID 2>/dev/null || true
    kill $PID 2>/dev/null || true
    wait $PID 2>/dev/null || true
    PID=
}
expect() {
    if [ "$(tr '\n' ';' < "$M/calls")" = "$2" ]; then echo "ok   $1"
    else echo "FAIL $1: $(tr '\n' ';' < "$M/calls") (want $2)"; fails=$((fails + 1)); fi
}
status() {
    case "$($SH "$T/status.sh")" in
        "$1"*) echo "ok   status: $1" ;;
        *) echo "FAIL status: $($SH "$T/status.sh") (want $1)"; fails=$((fails + 1)) ;;
    esac
}
JSON='I/ECO: {"a":1,"outTemperature":-3,"b":2}'

fresh; echo "$JSON" > "$M/logcat"; start
expect "cold, no Car Controls: the wheel only" "com.hkmc.vr 16 i32 1;"
status "on turned the heat on"

: > "$M/calls"; start quiet
expect "only once per start" ""
echo boot-2 > "$M/bootid"; start
expect "again on the next start" "com.hkmc.vr 16 i32 1;"

fresh; echo 'I/ECO: {"outTemperature":20}' > "$M/logcat"; start
expect "warm: nothing" ""
status "on warm enough"

fresh; echo "$JSON" > "$M/logcat"
cat > "$M/settings" <<'EOF'
Row: 0 key=threshold_f, value=50
Row: 1 key=wheel, value=0
Row: 2 key=seat_drv, value=3
Row: 3 key=seat_pass, value=1
Row: 4 key=PATH, value=1
Row: 5 key=seat_pass; x, value=$(x)
EOF
start
expect "settings: seats, levels mapped, nothing else read" "com.hkmc.micom.usm 213 i32 8;com.hkmc.micom.usm 214 i32 6;"

fresh; echo "x setOutsideTempUIAdvanced::temp = 8 y" > "$M/logcat"
echo 'Row: 0 key=threshold_f, value=40' > "$M/settings"; start
expect "dashboard in F: 8 is cold" "com.hkmc.vr 16 i32 1;"
fresh; echo "x setOutsideTempUIAdvanced::temp = 8 y" > "$M/logcat"
printf 'Row: 0 key=threshold_f, value=40\nRow: 1 key=ui_temp_is_c, value=1\n' > "$M/settings"; start
expect "dashboard in C: 8 is 46F" ""

fresh; start
expect "no temperature: nothing" ""
status "on couldn't read"

fresh; echo 'I/ECO: {"outTemperature":999}' > "$M/logcat"; start
expect "an impossible temperature: nothing" ""

fresh; echo "$JSON" > "$M/logcat"; touch "$M/no-seats"
echo 'Row: 0 key=seat_drv, value=2' > "$M/settings"; start
expect "a method this car lacks is never called" "com.hkmc.vr 16 i32 1;"
status "error the car didn't accept: driver"

fresh; echo "$JSON" > "$M/logcat"; touch "$M/refuse"; start
status "error the car didn't accept: wheel"

if [ $fails -gt 0 ]; then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
