#!/system/bin/sh
# One line: on|off|error <text>
D=${0%/*}
. "$D/common.sh"

if is_ours; then
    pending && echo "on restart the head unit to apply" || echo "on start-up screen skipped"
elif is_stock; then
    pending && echo "off restart the head unit to apply" || echo "off stock start-up screen"
else
    echo "error SystemUI is neither stock nor this tweak's - leaving it alone"
fi
