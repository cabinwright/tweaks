#!/system/bin/sh
# Install the patched SystemUI (see common.sh). Never reboots; exit 0 = installed.
D=${0%/*}
. "$D/common.sh"

if is_ours; then echo "already on"; exit 0; fi
is_stock || fail "SystemUI on /system isn't the stock version this tweak is made for - refusing"

# 1. rebuild the patched apk from the stock files; the tool checks the delta's md5s itself
{ rm -rf "$WORK" && mkdir -p "$WORK/data/dalvik-cache"; } || fail "mkdir $WORK"
kp delta "$D/systemui.lpd" $APP/SystemUI.odex "$WORK/classes.dex" || fail "rebuilding the patched code"
kp zipadd $APP/SystemUI.apk "$WORK/classes.dex" "$WORK/SystemUI.apk" || fail "packing the apk"
[ "$(sum "$WORK/SystemUI.apk")" = $SUM_OURS ] || fail "rebuilt apk isn't the expected one"

# 2. the stock odex doesn't match the new apk, so optimize it to a new one
ANDROID_DATA="$WORK/data" /system/bin/dexopt --preopt "$WORK/SystemUI.apk" "$WORK/SystemUI.odex" "m=y,u=n" || fail "optimizing the apk"

# 3. swap both in
kt file replace $APP/SystemUI.apk "$WORK/SystemUI.apk" || fail "replacing SystemUI.apk"
kt file replace $APP/SystemUI.odex "$WORK/SystemUI.odex" || fail "replacing SystemUI.odex"
rm -rf "$WORK"
mark_pending
echo "installed - restart the head unit to apply"
