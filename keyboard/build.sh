#!/bin/sh
# Builds the keyboard-fix delta: a classes.dex with the keyboard patch (patch.py),
# stored as a delta against the car's stock PinyinIME.odex, so the tweak rebuilds it on the
# car from the car's own file (tweaks/keyboard-fix/enable.sh) and nothing of the head unit's ships.
# On the car the dex is added to the stock PinyinIME.apk, untouched (the head unit's signed manifest and
# resources); as with the Cabinwright launcher hook, only the manifest is signature-checked for
# /system apps on this firmware.
#
# usage: keyboard/build.sh <stock dir> [out.lpd]
#   <stock dir> holds PinyinIME.apk, PinyinIME.odex and framework/ from the car
#   (adb pull /system/app/PinyinIME.apk, .odex, and /system/framework)
# Needs bsdiff4 for tools/mkdelta.py: PYTHON=<python with bsdiff4==1.3.1> (default python3),
# and the menu checkout (CABINWRIGHT_SDK, default ../menu) for tweakpatch, which packs the
# patched apk exactly as the car does to print its checksum (SUM_OURS in
# package/tweaks/keyboard-fix/common.sh).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
STOCK=$(cd "$1" && pwd)
OUT=${2:-$HERE/../package/tweaks/keyboard-fix/keyboard.lpd}
PYTHON=${PYTHON:-python3}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
JDK=${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}
JAVA=$JDK/bin/java

md5of() { if command -v md5 >/dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi; }

# only the exact stock keyboard this patch was written against (firmware 260507)
SUM_APK=a0dea3339f1b075c7edfb50ecf65ee4a
SUM_ODEX=8fe419474dab25262728e7a106362891
[ "$(md5of "$STOCK/PinyinIME.apk")" = $SUM_APK ] || { echo "not the stock PinyinIME.apk" >&2; exit 1; }
[ "$(md5of "$STOCK/PinyinIME.odex")" = $SUM_ODEX ] || { echo "not the stock PinyinIME.odex" >&2; exit 1; }

# smali 2.5.2, checked
TOOLS=$HERE/tools
mkdir -p "$TOOLS"
fetch() {
    [ -f "$TOOLS/$1" ] || curl -sSL -o "$TOOLS/$1" "https://bitbucket.org/JesusFreke/smali/downloads/$1"
    echo "$2  $TOOLS/$1" | shasum -a 256 -c -s 2>/dev/null || { echo "$1 checksum mismatch" >&2; rm -f "$TOOLS/$1"; exit 1; }
}
fetch baksmali-2.5.2.jar d3116248cce4f82ec5a31eb7f95ee75daff42ddf6eed0ab573973dc53fbad2e5
fetch smali-2.5.2.jar 9544299578b16f771d8aa8eaefe0d3718ca03478c16f3c356f2fcf1366bfb116

# obfuscated classes differ only in case: work on a case-sensitive volume (a disk image
# on macOS; Linux file systems already are)
WORK=$(mktemp -d)
if [ "$(uname)" = Darwin ]; then
    trap 'hdiutil detach -quiet "$WORK/cs" 2>/dev/null; rm -rf "$WORK"' EXIT
    hdiutil create -quiet -size 200m -fs "Case-sensitive APFS" -volname keyboard "$WORK/cs.dmg"
    hdiutil attach -quiet -nobrowse -mountpoint "$WORK/cs" "$WORK/cs.dmg"
else
    trap 'rm -rf "$WORK"' EXIT
    mkdir "$WORK/cs"
fi
CS=$WORK/cs

BCP=core.jar:conscrypt.jar:okhttp.jar:core-junit.jar:bouncycastle.jar:ext.jar:framework.jar:framework2.jar:telephony-common.jar:voip-common.jar:mms-common.jar:android.policy.jar:services.jar:apache-xml.jar:webviewchromium.jar:automotive.jar
# -a 18: -a 19 mis-maps KitKat instance fields (Leafia's notes)
"$JAVA" -jar "$TOOLS/baksmali-2.5.2.jar" x -a 18 -d "$STOCK/framework" -b "$BCP" \
    "$STOCK/PinyinIME.odex" -o "$CS/smali"
python3 -I "$HERE/patch.py" "$CS/smali"
# -j 1: more threads write a different (equivalent) dex each run
"$JAVA" -jar "$TOOLS/smali-2.5.2.jar" a -j 1 --api 18 "$CS/smali" -o "$CS/classes.dex"

mkdir -p "$(dirname "$OUT")"
"$PYTHON" -I "$HERE/../tools/mkdelta.py" "$STOCK/PinyinIME.odex" "$CS/classes.dex" "$OUT"
echo "classes.dex $(md5of "$CS/classes.dex")"

# the patched apk, as the car's tweakpatch packs it
CABINWRIGHT_SDK=${CABINWRIGHT_SDK:-$HERE/../../sdk}
export CABINWRIGHT_SDK
sh "$HERE/../patch/build.sh" --classes "$WORK/tweakpatch.jar" >/dev/null
"$JAVA" -cp "$WORK/tweakpatch.jar" app.cabinwright.tweaks.patch.Main zipadd "$STOCK/PinyinIME.apk" "$CS/classes.dex" "$CS/PinyinIME.apk"
echo "SUM_OURS=$(md5of "$CS/PinyinIME.apk")"
