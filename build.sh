#!/bin/sh
# Builds the cabinwright.tweaks NEMESIS package: package/ (tweaksd, the tweak folders, NEMESIS.data),
# the patch tool for SystemUI-type tweaks (patch/, into lib/tweakpatch.jar) and the Tweaks app,
# which uses the Cabinwright API (../menu/api) to show up in All Menus.
# Install over ADB:
#   adb push dist/cabinwright.tweaks.zip /data/local/tmp/
#   adb shell "nemesis install [--update] /data/local/tmp/cabinwright.tweaks.zip"
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
CABINWRIGHT_MENU=${CABINWRIGHT_MENU:-$ROOT/../menu}
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/package/." "$STAGE/"
mkdir -p "$STAGE/app" "$STAGE/lib"
sh "$ROOT/patch/build.sh" "$STAGE/lib/tweakpatch.jar" >/dev/null
sh "$CABINWRIGHT_MENU/api/tools/build-app.sh" --ui "$ROOT/app" "$STAGE/app/tweaks.apk" >/dev/null
find "$STAGE" -name .DS_Store -delete
mkdir -p "$ROOT/dist" && rm -f "$ROOT/dist/cabinwright.tweaks.zip"
(cd "$STAGE" && zip -qrX "$ROOT/dist/cabinwright.tweaks.zip" .)
echo "$ROOT/dist/cabinwright.tweaks.zip"
