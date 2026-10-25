#!/bin/sh
# Builds the on-car patch tool (dev.kiatweaks.patch.Main) into a dex jar for app_process.
# usage: patch/build.sh <out.jar>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE/build/kiapatch.jar}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BUILD_TOOLS=${BUILD_TOOLS:-$SDK/build-tools/29.0.2}
ANDROID_JAR=$SDK/platforms/android-23/android.jar
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/c" "$WORK/d"
javac -source 8 -target 8 -Xlint:-options -bootclasspath "$ANDROID_JAR" -d "$WORK/c" \
    $(find "$HERE/src" -name '*.java')
"$BUILD_TOOLS/d8" --release --min-api 19 --lib "$ANDROID_JAR" --output "$WORK/d" \
    $(find "$WORK/c" -name '*.class')
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# app_process needs a jar (a bare .dex has no classes.dex entry for dalvik to cache)
(cd "$WORK/d" && zip -q -X "$OUT" classes.dex)
echo "$OUT"
