#!/system/bin/sh
# Put the stock SystemUI back from the backup (see common.sh). Never reboots.
D=${0%/*}
. $D/common.sh

if is_stock; then echo "already off"; exit 0; fi
backup_ok $B || { backup_ok $OLD_B && B=$OLD_B; } || fail "no stock backup - nothing changed"

/system/xbin/nemesis remount rw >/dev/null 2>&1 || fail "remount rw"
cp $B/SystemUI.apk $APP/SystemUI.apk.new && cp $B/SystemUI.odex $APP/SystemUI.odex.new || fail "copy stock files"
chmod 644 $APP/SystemUI.apk.new $APP/SystemUI.odex.new
mv $APP/SystemUI.apk.new $APP/SystemUI.apk && mv $APP/SystemUI.odex.new $APP/SystemUI.odex || fail "move stock files into place"
rm -f /data/dalvik-cache/*SystemUI* 2>/dev/null
sync
/system/xbin/nemesis remount ro >/dev/null 2>&1
is_stock || fail "files on /system don't match stock after the copy"
mark_pending
echo "stock SystemUI restored - restart the head unit to apply"
