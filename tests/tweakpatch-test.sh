#!/bin/sh
# Host test: tweakpatch (patch/), as R8 shrinks it, on the host's JVM against fixtures from
# tests/tweakpatch-fixtures.py: md5, a delta rebuilt byte for byte and the deltas it must
# refuse, and zipadd's exact output. The car runs the same code as a dex under app_process.
# Needs the menu checkout for the pinned tools (CABINWRIGHT_MENU, default ../menu) and python3.
# usage: sh tests/tweakpatch-test.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CABINWRIGHT_MENU=${CABINWRIGHT_MENU:-$ROOT/../menu}
export CABINWRIGHT_MENU
JDK=${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
sh "$ROOT/patch/build.sh" --classes "$W/tweakpatch.jar" >/dev/null
mkdir "$W/fx"
python3 -I "$ROOT/tests/tweakpatch-fixtures.py" "$W/fx"
cd "$W/fx"

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
kp() { "$JDK/bin/java" -cp "$W/tweakpatch.jar" dev.cabinwright.tweaks.patch.Main "$@"; }
md5of() { if command -v md5 >/dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi; }
# refuses <name> <expected message part> <command...>: exit 1, the message, and no output file
refuses() {
    name=$1 want=$2
    shift 2
    rm -f out
    if kp "$@" 2>err; then bad "$name: accepted"; return; fi
    if ! grep -q "$want" err; then bad "$name: said $(cat err)"; return; fi
    if [ -e out ]; then bad "$name: wrote out"; return; fi
    ok "$name"
}

if [ "$(kp md5 src)" = "$(md5of src)" ]; then ok "md5"; else bad "md5: $(kp md5 src)"; fi
if kp delta good.lpd src out && cmp -s out dst && [ ! -e out.tmp ]; then ok "delta rebuilds dst"; else bad "delta rebuilds dst"; fi
refuses "delta: wrong source" "isn't the original this delta needs" delta good.lpd dst out
refuses "delta: wrong result" "doesn't match the delta's result" delta bad-dst.lpd src out
refuses "delta: truncated" "truncated delta" delta short.lpd src out
refuses "delta: not a delta" "not a delta" delta src src out
if kp zipadd app.apk dex out && cmp -s out zipadd.apk; then ok "zipadd output"; else bad "zipadd output"; fi
if python3 -I -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None
assert z.read("classes.dex") == open(sys.argv[2], "rb").read()' out dex; then ok "zipadd: a valid zip"; else bad "zipadd: a valid zip"; fi
cp out with-dex.apk
refuses "zipadd: has classes.dex" "already has classes.dex" zipadd with-dex.apk dex out
refuses "zipadd: not a zip" "not a zip" zipadd dex dex out
refuses "usage" "usage:" frobnicate

if [ $fails -gt 0 ]; then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
