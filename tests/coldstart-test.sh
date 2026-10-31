#!/bin/sh
# Host test: the coldstart-heat tweak against a stub kt. KT_SH=mksh|bash picks the shell.
# usage: sh tests/coldstart-test.sh
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/package/tweaks/coldstart-heat
SH=${KT_SH:-sh}
W=$(mktemp -d)
PID=
trap '[ -n "$PID" ] && kill $PID 2>/dev/null; rm -rf "$W"' EXIT
fails=0
M=$W/car
export TWEAK_DATA="$W/data" COLDSTART_WAIT=4 PATH="$W/stubs:$PATH"
mkdir -p "$W/stubs"
cat > "$W/stubs/kt" <<STUB
#!/bin/sh
case "\$1" in
    dump) cat $M/dump 2>/dev/null ;;
    binder)
        shift
        echo "\$*" >> $M/calls
        if [ -f $M/refuse ]; then echo "Result: Parcel(ffffffb4 00000000)"; else echo "Result: Parcel(00000000    '....')"; fi ;;
esac
STUB
cat > "$W/stubs/cat" <<STUB
#!/bin/sh
case "\$1" in /proc/sys/kernel/random/boot_id) exec /bin/cat $M/bootid ;; *) exec /bin/cat "\$@" ;; esac
STUB
cat > "$W/stubs/sleep" <<'STUB'
#!/bin/sh
[ "$1" = 3600 ] && exec /bin/sleep 3600
exit 0
STUB
chmod 755 "$W"/stubs/*
# <raw F> <decoded F> <raw C> <decoded C>, as the climate service prints them
dump() {
    cat > "$M/dump" <<DUMP
  mTempUnit: 2
  mAmbientTempC: $4
  mAmbientTempF: $2
  mAmbientTempStateC: 255
  AmbientTempC : 0x$3
  AmbientTempF : 0x$1
DUMP
}
fresh() { rm -rf "$M" "$TWEAK_DATA"; mkdir -p "$M" "$TWEAK_DATA"; echo boot-1 > "$M/bootid"; : > "$M/calls"; }
# runs run.sh until it idles
start() {
    $SH "$T/run.sh" > "$W/log" 2>&1 &
    PID=$!
    /bin/sleep 0.5
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
BOTH="com.hkmc.vr 16 i32 1;com.hkmc.micom.usm 213 i32 8;"

fresh; dump 52 42.0 ff -40.0; start
expect "42F: wheel and seat" "$BOTH"
status "on turned the heat on"

: > "$M/calls"; start
expect "only once per start" ""
echo boot-2 > "$M/bootid"; start
expect "again on the next start" "$BOTH"

fresh; dump 5a 50.0 ff -40.0; start
expect "exactly the threshold: nothing" ""
status "on warm enough"

fresh; dump 28 0.0 ff -40.0; start
expect "a real 0F is cold" "$BOTH"
fresh; dump 1e -10.0 ff -40.0; start
expect "a real -10F is cold" "$BOTH"

fresh; dump ff -40.0 0c 6.0; start
expect "a car in Celsius: 6C is 42F" "$BOTH"
fresh; dump ff -40.0 28 20.0; start
expect "a car in Celsius: 20C is warm" ""

fresh; dump 00 0.0 00 0.0; start
expect "before the first reading: nothing, not cold" ""
status "on couldn't read"
fresh; dump ff -40.0 ff -40.0; start
expect "no valid reading: nothing" ""
fresh; start
expect "no dump: nothing" ""
fresh; dump 52 999.0 ff -40.0; start
expect "an impossible temperature: nothing" ""

fresh; dump 52 42.0 ff -40.0; touch "$M/refuse"; start
status "error the car didn't accept: steering wheel driver's seat"

if [ $fails -gt 0 ]; then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
