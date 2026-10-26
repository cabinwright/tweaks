# Shared by enable.sh, disable.sh and status.sh (sourced; $D is this folder).
# The head unit's SystemUI asks for consent at every start; the patch (systemui/patch.py) makes
# ConsentScreenUI.start() record the agreement and skip building the screen. The patched
# classes.dex is rebuilt here from the car's own stock SystemUI.odex (systemui.lpd), added to
# The stock SystemUI.apk, and installed in its place; the stock pair is backed up first.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
export ANDROID_ROOT=/system ANDROID_ASSETS=/system/app
export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
APP=/system/priv-app
B=/data/nemesis/backup/cabinwright.tweaks.systemui
LEGACY_B=/data/nemesis/backup/kia-tweaks.systemui   # kia.tweaks' (this package's earlier name); read only
OLD_B=/data/nemesis/backup/ev6.systemui      # taken by the earlier ev6-fixes test install
WORK=/data/nemesis/cabinwright/tweaks/skip-consent
PENDING=/data/nemesis/cabinwright/tweaks/skip-consent.pending
KP=$D/../../lib/tweakpatch.jar
SUM_APK=512fa1835649e710d91deeb37c90433d       # stock, firmware 260507
SUM_ODEX=8abb72b9715bc8e4746ac9ee3b03ab39
SUM_OURS=15e8195ea7c5099fc0cb4ba734370ddc      # stock apk + patched classes.dex, as built here
SUM_OURS_OLD=01b0f1111c2e1a7e4ec550f0403bb840  # the same, as the ev6-fixes test build packed it

sum() { md5 "$1" 2>/dev/null | while read -r s f; do echo "$s"; done; }
fail() { echo "FAIL: $1"; /system/xbin/nemesis remount ro >/dev/null 2>&1; rm -rf $WORK; exit 1; }

is_stock() { [ "$(sum $APP/SystemUI.apk)" = $SUM_APK ] && [ "$(sum $APP/SystemUI.odex)" = $SUM_ODEX ]; }
is_ours() { s=$(sum $APP/SystemUI.apk); [ "$s" = $SUM_OURS ] || [ "$s" = $SUM_OURS_OLD ]; }
backup_ok() { [ "$(sum $1/SystemUI.apk)" = $SUM_APK ] && [ "$(sum $1/SystemUI.odex)" = $SUM_ODEX ]; }

# the patch tool runs in its own dalvik (root here can't write /data/dalvik-cache)
kp() {
    ANDROID_DATA=$WORK/data CLASSPATH=$KP app_process /system/bin dev.cabinwright.tweaks.patch.Main "$@"
}

# a change made during this boot only shows after a restart
mark_pending() { mkdir -p ${PENDING%/*} && cat /proc/sys/kernel/random/boot_id > $PENDING; }
pending() { [ -f $PENDING ] && [ "$(cat $PENDING)" = "$(cat /proc/sys/kernel/random/boot_id)" ]; }
