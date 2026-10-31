# Shared by enable.sh, disable.sh and status.sh (sourced; $D is this folder).
# The stock keyboard crashes on a private IME option with no "=" (keyboard/patch.py). The patched
# classes.dex is rebuilt in $TWEAK_DATA from the car's own stock PinyinIME.odex (keyboard.lpd),
# added to the stock PinyinIME.apk and optimized there, all as this tweak's own uid; only the
# final swap into /system goes through `kt file replace`, which the runner records so that
# turning the tweak off puts the stock files back.
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
export ANDROID_ROOT=/system ANDROID_ASSETS=/system/app
export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
APP=/system/app
WORK=$TWEAK_DATA/work
PENDING=$TWEAK_DATA/pending
KP=$D/../../lib/tweakpatch.jar
SUM_APK=a0dea3339f1b075c7edfb50ecf65ee4a       # stock, firmware 260507 (tweak.conf's needs)
SUM_ODEX=8fe419474dab25262728e7a106362891
SUM_OURS=8483af7ab6670beed28e784779b0c943      # stock apk + patched classes.dex, as built here

sum() { md5 "$1" 2>/dev/null | while read -r s _; do echo "$s"; done; }
fail() { echo "FAIL: $1"; rm -rf "$WORK"; exit 1; }

is_stock() { [ "$(sum $APP/PinyinIME.apk)" = $SUM_APK ] && [ "$(sum $APP/PinyinIME.odex)" = $SUM_ODEX ]; }
is_ours() { [ "$(sum $APP/PinyinIME.apk)" = $SUM_OURS ]; }

# the patch tool runs in a dalvik of its own, with its cache in $WORK
kp() {
    ANDROID_DATA=$WORK/data CLASSPATH=$KP /system/bin/app_process /system/bin app.cabinwright.tweaks.patch.Main "$@"
}

# a change made during this boot only shows after a restart
mark_pending() { cat /proc/sys/kernel/random/boot_id > "$PENDING"; }
pending() { [ -f "$PENDING" ] && [ "$(cat "$PENDING")" = "$(cat /proc/sys/kernel/random/boot_id)" ]; }
