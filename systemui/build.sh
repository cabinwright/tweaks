#!/bin/sh
# Builds the skip-consent delta: a classes.dex with the consent-screen patch (patch.py),
# stored as a delta against the car's stock SystemUI.odex, so the tweak rebuilds it on the
# car from the car's own file (tweaks/skip-consent/enable.sh) and nothing of the head unit's ships.
# On the car the dex is added to the stock SystemUI.apk, untouched (the head unit's signed manifest and
# resources); as with the Cabinwright launcher hook, only the manifest is signature-checked for
# /system apps on this firmware.
#
# usage: systemui/build.sh <stock dir> [out.lpd]
#   <stock dir> holds SystemUI.apk, SystemUI.odex and framework/ from the car
#   (adb pull /system/priv-app/SystemUI.apk, .odex, and /system/framework)
# Needs bsdiff4 for tools/mkdelta.py: PYTHON=<python with bsdiff4==1.3.1> (default python3).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
STOCK=$(cd "$1" && pwd)
OUT=${2:-$HERE/../package/tweaks/skip-consent/systemui.lpd}
PYTHON=${PYTHON:-python3}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
JDK=${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}
JAVA=$JDK/bin/java

md5of() { if command -v md5 >/dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi; }

# only the exact stock SystemUI this patch was written against (firmware 260507)
SUM_APK=512fa1835649e710d91deeb37c90433d
SUM_ODEX=8abb72b9715bc8e4746ac9ee3b03ab39
[ "$(md5of "$STOCK/SystemUI.apk")" = $SUM_APK ] || { echo "not the stock SystemUI.apk" >&2; exit 1; }
[ "$(md5of "$STOCK/SystemUI.odex")" = $SUM_ODEX ] || { echo "not the stock SystemUI.odex" >&2; exit 1; }

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
    hdiutil create -quiet -size 600m -fs "Case-sensitive APFS" -volname systemui "$WORK/cs.dmg"
    hdiutil attach -quiet -nobrowse -mountpoint "$WORK/cs" "$WORK/cs.dmg"
else
    trap 'rm -rf "$WORK"' EXIT
    mkdir "$WORK/cs"
fi
CS=$WORK/cs

BCP=core.jar:conscrypt.jar:okhttp.jar:core-junit.jar:bouncycastle.jar:ext.jar:framework.jar:framework2.jar:telephony-common.jar:voip-common.jar:mms-common.jar:android.policy.jar:services.jar:apache-xml.jar:webviewchromium.jar:automotive.jar
# -a 18: -a 19 mis-maps KitKat instance fields (Leafia's notes)
"$JAVA" -jar "$TOOLS/baksmali-2.5.2.jar" x -a 18 -d "$STOCK/framework" -b "$BCP" \
    "$STOCK/SystemUI.odex" -o "$CS/smali"
python3 -I "$HERE/patch.py" "$CS/smali"
# -j 1: more threads write a different (equivalent) dex each run
"$JAVA" -jar "$TOOLS/smali-2.5.2.jar" a -j 1 --api 18 "$CS/smali" -o "$CS/classes.dex"

mkdir -p "$(dirname "$OUT")"
"$PYTHON" -I "$HERE/../tools/mkdelta.py" "$STOCK/SystemUI.odex" "$CS/classes.dex" "$OUT"
echo "classes.dex $(md5of "$CS/classes.dex")"
