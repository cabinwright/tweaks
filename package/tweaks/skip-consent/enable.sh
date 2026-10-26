#!/system/bin/sh
# Install the patched SystemUI (see common.sh). Never reboots; exit 0 = installed.
D=${0%/*}
. $D/common.sh

if is_ours; then echo "already on"; exit 0; fi

# 1. stock backup, taken once and only from the stock files
if backup_ok $B; then
    echo "stock backup present"
elif backup_ok $LEGACY_B; then
    # tweaksd normally copies it when it imports kia.tweaks' data; left as it is there
    mkdir -p $B && cp $LEGACY_B/SystemUI.apk $LEGACY_B/SystemUI.odex $B/ || fail "copy backup"
    backup_ok $B || fail "backup copy doesn't match stock"
    echo "copied stock backup from $LEGACY_B"
elif backup_ok $OLD_B; then
    mkdir -p $B && cp $OLD_B/SystemUI.apk $OLD_B/SystemUI.odex $B/ || fail "copy backup"
    backup_ok $B || fail "backup copy doesn't match stock"
    rm -rf $OLD_B
    echo "moved stock backup from $OLD_B"
elif is_stock; then
    mkdir -p $B && cp $APP/SystemUI.apk $APP/SystemUI.odex $B/ || fail "backup copy"
    backup_ok $B || fail "backup doesn't match stock"
    echo "backed up stock SystemUI to $B"
else
    fail "SystemUI on /system isn't stock and there is no stock backup - refusing"
fi

# 2. rebuild the patched apk from the backup; the tool checks the delta's md5s itself
rm -rf $WORK && mkdir -p $WORK/data/dalvik-cache || fail "mkdir $WORK"
kp delta $D/systemui.lpd $B/SystemUI.odex $WORK/classes.dex || fail "rebuilding the patched code"
kp zipadd $B/SystemUI.apk $WORK/classes.dex $WORK/SystemUI.apk || fail "packing the apk"
[ "$(sum $WORK/SystemUI.apk)" = $SUM_OURS ] || fail "rebuilt apk isn't the expected one"

# 3. swap it in; the stock odex no longer matches it, so re-optimize
/system/xbin/nemesis remount rw >/dev/null 2>&1 || fail "remount rw"
cp $WORK/SystemUI.apk $APP/SystemUI.apk.new || fail "copy new apk"
chmod 644 $APP/SystemUI.apk.new
mv $APP/SystemUI.apk.new $APP/SystemUI.apk || fail "move new apk into place"
rm -f $APP/SystemUI.odex
if /system/bin/dexopt --preopt $APP/SystemUI.apk $APP/SystemUI.odex "m=y,u=n"; then
    chmod 644 $APP/SystemUI.odex
else
    rm -f $APP/SystemUI.odex
    echo "dexopt failed - the next start optimizes it into dalvik-cache"
fi
sync
/system/xbin/nemesis remount ro >/dev/null 2>&1
rm -rf $WORK
mark_pending
echo "installed - restart the head unit to apply"
