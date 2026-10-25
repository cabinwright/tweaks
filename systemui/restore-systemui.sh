#!/system/bin/sh
# Rescue: restore Kia's stock SystemUI from the skip-consent tweak's backup, then reboot.
# For when the head unit can't reach the Tweaks app; normally the tweak's own switch does
# this. Run from the USB stick (NEMESIS.data type=execute), which runs with full root.
# Log: systemui-restore.log on the stick.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
B=/data/nemesis/backup/kia-tweaks.systemui
[ -d $B ] || B=/data/nemesis/backup/ev6.systemui   # earlier test install
APP=/system/priv-app
SUM_APK=512fa1835649e710d91deeb37c90433d
SUM_ODEX=8abb72b9715bc8e4746ac9ee3b03ab39
L=/storage/usb0/systemui-restore.log
log() { echo "$(date) $1" >> $L; }

sum() { md5 "$1" 2>/dev/null | while read -r s f; do echo "$s"; done; }

log "restore start"
if [ "$(sum $B/SystemUI.apk)" != $SUM_APK ] || [ "$(sum $B/SystemUI.odex)" != $SUM_ODEX ]; then
    log "FAIL: backup in $B is missing or not the stock files - nothing changed"
    exit 1
fi
if [ "$(sum $APP/SystemUI.apk)" = $SUM_APK ] && [ "$(sum $APP/SystemUI.odex)" = $SUM_ODEX ]; then
    log "already stock - nothing to do"
    exit 0
fi
/system/xbin/nemesis remount rw >> $L 2>&1 || { log "FAIL: remount rw"; exit 1; }
cp $B/SystemUI.apk $APP/SystemUI.apk && cp $B/SystemUI.odex $APP/SystemUI.odex
chmod 644 $APP/SystemUI.apk $APP/SystemUI.odex
chown root.root $APP/SystemUI.apk $APP/SystemUI.odex
rm -f /data/dalvik-cache/*SystemUI* /data/dalvik-cache/arm/*SystemUI* /cache/dalvik-cache/*SystemUI*
sync
/system/xbin/nemesis remount ro >> $L 2>&1
if [ "$(sum $APP/SystemUI.apk)" = $SUM_APK ] && [ "$(sum $APP/SystemUI.odex)" = $SUM_ODEX ]; then
    log "stock SystemUI restored - rebooting"
    sync
    reboot
fi
log "FAIL: files on /system don't match stock after copy - not rebooting"
exit 1
