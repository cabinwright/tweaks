#!/system/bin/sh
# One line: on|off|error <text>
D=${0%/*}
. "$D/common.sh"

if is_ours; then
    pending && echo "on restart the head unit to apply" || echo "on keyboard fixed"
elif is_stock; then
    pending && echo "off restart the head unit to apply" || echo "off stock keyboard"
else
    echo "error The keyboard is neither stock nor this tweak's - leaving it alone"
fi
