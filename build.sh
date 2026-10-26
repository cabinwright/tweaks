#!/bin/sh
# Builds the cabinwright.tweaks NEMESIS package: package/ (tweaksd, the tweak folders, NEMESIS.data),
# the patch tool for SystemUI-type tweaks (patch/, into lib/tweakpatch.jar) and the Tweaks app,
# which uses the Cabinwright API (../menu/api) to show up in All Menus. Both are Kotlin, built
# with the menu checkout's pinned tools (CABINWRIGHT_MENU) and shrunk by R8, whose name maps go
# to dist/ for reading stack traces (retrace).
# Install over ADB:
#   adb push dist/cabinwright.tweaks.zip /data/local/tmp/
#   adb shell "nemesis install [--update] /data/local/tmp/cabinwright.tweaks.zip"
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
CABINWRIGHT_MENU=${CABINWRIGHT_MENU:-$ROOT/../menu}
export CABINWRIGHT_MENU
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/package/." "$STAGE/"
mkdir -p "$STAGE/app" "$STAGE/lib" "$ROOT/dist"
TWEAKPATCH_MAP=$ROOT/dist/cabinwright.tweaks-tweakpatch.map \
    sh "$ROOT/patch/build.sh" "$STAGE/lib/tweakpatch.jar" >/dev/null
CABINWRIGHT_MAP=$ROOT/dist/cabinwright.tweaks.map \
    sh "$CABINWRIGHT_MENU/api/tools/build-app.sh" --ui "$ROOT/app" "$STAGE/app/tweaks.apk" >/dev/null
find "$STAGE" -name .DS_Store -delete
rm -f "$ROOT/dist/cabinwright.tweaks.zip"
(cd "$STAGE" && zip -qrX "$ROOT/dist/cabinwright.tweaks.zip" .)
echo "$ROOT/dist/cabinwright.tweaks.zip"
