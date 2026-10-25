#!/system/bin/sh
# One line for tweaksd: on|off|error <text>, from run.sh's check mode
# ("zone=Mobis/UTC-05:00 offset=5 rule=M3.2.0,M11.1.0 want=1 kia=1").
r=$(sh "${0%/*}/run.sh" check)
zone=${r#zone=}; zone=${zone%% *}
want=${r#*want=}; want=${want%% *}
kia=${r#*kia=}; kia=${kia%% *}
if [ -z "$want" ]; then
    echo "error time zone ${zone:-unset} isn't one of Kia's UTC-offset zones"
elif [ -z "$kia" ]; then
    echo "error can't read Kia's daylight saving time setting"
elif [ "$want" = "$kia" ]; then
    [ "$want" = 1 ] && echo "on daylight saving time (zone ${zone#Mobis/})" || echo "on standard time (zone ${zone#Mobis/})"
else
    # run.sh fixes this within a minute while the tweak is on
    [ "$want" = 1 ] && echo "off daylight saving time should be on" || echo "off daylight saving time should be off"
fi
