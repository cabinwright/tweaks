#!/bin/sh
# Builds the cabinwright.tweaks NEMESIS package: package/ (the tweak folders, NEMESIS.data), the
# patch tool for SystemUI-type tweaks (patch/, into lib/tweakpatch.jar) and the Tweaks app,
# which uses the Cabinwright API (sdk/api) to show up in All Menus and to reach the store's
# tweak runner through its broker (CarBroker). Both are Kotlin, built
# with the menu checkout's pinned tools (CABINWRIGHT_SDK) and shrunk by R8, whose name maps go
# to dist/ for reading stack traces (retrace).
# The store installs it from the index (and writes its NEMESIS.data itself).
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
CABINWRIGHT_SDK=${CABINWRIGHT_SDK:-$ROOT/sdk}
export CABINWRIGHT_SDK
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/package/." "$STAGE/"
mkdir -p "$STAGE/lib" "$ROOT/dist"
TWEAKPATCH_MAP=$ROOT/dist/cabinwright.tweaks-tweakpatch.map \
    sh "$ROOT/patch/build.sh" "$STAGE/lib/tweakpatch.jar" >/dev/null
CABINWRIGHT_MAP=$ROOT/dist/cabinwright.tweaks.map \
    sh "$CABINWRIGHT_SDK/api/tools/build-app.sh" --ui --broker "$ROOT/app" "$STAGE/tweaks.apk" >/dev/null
find "$STAGE" -name .DS_Store -delete
rm -f "$ROOT/dist/cabinwright.tweaks.zip"
(cd "$STAGE" && zip -qrX "$ROOT/dist/cabinwright.tweaks.zip" .)
echo "$ROOT/dist/cabinwright.tweaks.zip"
