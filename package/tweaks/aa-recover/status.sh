#!/system/bin/sh
# One line for tweaksd: on|off|error <text>. Shows run.sh's last action, if any.
L=/data/nemesis/kia-tweaks/last/aa-recover
if [ -s $L ]; then
    read -r when what < $L
    ago=$(( ($(date +%s) - when) / 60 ))
    # before the clock is set at start-up, times are meaningless
    [ "$when" -lt 1577836800 ] && at="at start-up" || { [ $ago -lt 120 ] && at="$ago min ago" || at="$((ago / 60)) h ago"; }
    echo "on $what ($at)"
else
    echo "on watching the Android Auto receiver"
fi
