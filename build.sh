#!/bin/sh
# Builds the kia.tweaks NEMESIS package: package/ (tweaksd, the tweak folders, NEMESIS.data),
# the patch tool for SystemUI-type tweaks (patch/, into lib/kiapatch.jar) and the Tweaks app,
# which uses the kia-menu API (../kia-menu/api) to show up in All Menus.
# Install over ADB:
#   adb push dist/kia.tweaks.zip /data/local/tmp/
#   adb shell "nemesis install [--update] /data/local/tmp/kia.tweaks.zip"
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
KIA_MENU=${KIA_MENU:-$ROOT/../kia-menu}
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/package/." "$STAGE/"
mkdir -p "$STAGE/app" "$STAGE/lib"
sh "$ROOT/patch/build.sh" "$STAGE/lib/kiapatch.jar" >/dev/null
sh "$KIA_MENU/api/tools/build-app.sh" --ui "$ROOT/app" "$STAGE/app/kia-tweaks.apk" >/dev/null
find "$STAGE" -name .DS_Store -delete
mkdir -p "$ROOT/dist" && rm -f "$ROOT/dist/kia.tweaks.zip"
(cd "$STAGE" && zip -qrX "$ROOT/dist/kia.tweaks.zip" .)
echo "$ROOT/dist/kia.tweaks.zip"
