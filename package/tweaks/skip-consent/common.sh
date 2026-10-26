# Shared by enable.sh, disable.sh and status.sh (sourced; $D is this folder).
# The head unit's SystemUI asks for consent at every start; the patch (systemui/patch.py) makes
# ConsentScreenUI.start() record the agreement and skip building the screen. The patched
# classes.dex is rebuilt in $TWEAK_DATA from the car's own stock SystemUI.odex (systemui.lpd),
# added to the stock SystemUI.apk and optimized there, all as this tweak's own uid; only the
# final swap into /system goes through `kt file replace`, which the runner records so that
# turning the tweak off puts the stock files back.
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
export ANDROID_ROOT=/system ANDROID_ASSETS=/system/app
export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
APP=/system/priv-app
WORK=$TWEAK_DATA/work
PENDING=$TWEAK_DATA/pending
KP=$D/../../lib/tweakpatch.jar
SUM_APK=512fa1835649e710d91deeb37c90433d       # stock, firmware 260507 (tweak.conf's needs)
SUM_ODEX=8abb72b9715bc8e4746ac9ee3b03ab39
SUM_OURS=15e8195ea7c5099fc0cb4ba734370ddc      # stock apk + patched classes.dex, as built here

sum() { md5 "$1" 2>/dev/null | while read -r s _; do echo "$s"; done; }
fail() { echo "FAIL: $1"; rm -rf "$WORK"; exit 1; }

is_stock() { [ "$(sum $APP/SystemUI.apk)" = $SUM_APK ] && [ "$(sum $APP/SystemUI.odex)" = $SUM_ODEX ]; }
is_ours() { [ "$(sum $APP/SystemUI.apk)" = $SUM_OURS ]; }

# the patch tool runs in a dalvik of its own, with its cache in $WORK
kp() {
    ANDROID_DATA=$WORK/data CLASSPATH=$KP /system/bin/app_process /system/bin dev.cabinwright.tweaks.patch.Main "$@"
}

# a change made during this boot only shows after a restart
mark_pending() { cat /proc/sys/kernel/random/boot_id > "$PENDING"; }
pending() { [ -f "$PENDING" ] && [ "$(cat "$PENDING")" = "$(cat /proc/sys/kernel/random/boot_id)" ]; }
