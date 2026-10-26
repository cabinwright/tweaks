#!/bin/sh
# Builds the on-car patch tool (dev.cabinwright.tweaks.patch.Main, Kotlin) for app_process:
# compiled against Android 4.4's android.jar and shrunk by R8, with the pinned tools from the
# Cabinwright API's fetch-tools.sh (CABINWRIGHT_MENU, the menu checkout; default ../menu).
# --classes writes the shrunk class files instead of a dex (tests/tweakpatch-test.sh runs
# them on the host's JVM). TWEAKPATCH_MAP=<file> keeps R8's name map.
# usage: patch/build.sh [--classes] [out.jar]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
CABINWRIGHT_MENU=${CABINWRIGHT_MENU:-$HERE/../../menu}
CLASSES=
if [ "$1" = --classes ]; then
    CLASSES=1
    shift
fi
OUT=${1:-$HERE/build/tweakpatch.jar}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
JDK=${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}
FT=$(sh "$CABINWRIGHT_MENU/api/tools/fetch-tools.sh")
JAR=$FT/android-19.jar
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/c" "$WORK/out"
find "$HERE/src" -name '*.kt' >"$WORK/kt.txt"
JAVA_HOME=$JDK "$FT/kotlinc/bin/kotlinc" -jvm-target 1.8 -no-jdk -no-reflect -Werror \
    -Xno-param-assertions -Xno-call-assertions -Xno-receiver-assertions \
    -classpath "$JAR" -d "$WORK/c" "@$WORK/kt.txt"
(cd "$WORK/c" && "$JDK/bin/jar" cfM ../classes.jar .)
if [ -n "$CLASSES" ]; then set -- --classfile; else set -- --min-api 19; fi
"$JDK/bin/java" -cp "$FT/r8.jar" com.android.tools.r8.R8 --release "$@" --lib "$JAR" \
    --pg-conf "$CABINWRIGHT_MENU/api/tools/app-rules.pro" --pg-conf "$HERE/rules.pro" \
    --pg-map-output "${TWEAKPATCH_MAP:-$WORK/r8.map}" --output "$WORK/out" \
    "$WORK/classes.jar" "$FT/kotlinc/lib/kotlin-stdlib.jar"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# app_process needs a jar (a bare .dex has no classes.dex entry for dalvik to cache); R8 also
# copies the stdlib's resources (.kotlin_builtins, META-INF), which only Kotlin's reflection reads
if [ -n "$CLASSES" ]; then
    (cd "$WORK/out" && find . -name '*.class' | zip -q -X "$OUT" -@)
else
    (cd "$WORK/out" && zip -q -X "$OUT" classes.dex)
fi
echo "$OUT"
