#!/system/bin/sh
# The runner puts the stock SystemUI back from its own backup after this; this only notes
# that the head unit needs a restart to show it. Never reboots.
D=${0%/*}
. "$D/common.sh"

mark_pending
echo "restart the head unit to apply"
