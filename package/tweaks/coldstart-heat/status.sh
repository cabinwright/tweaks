#!/system/bin/sh
# One line for tweaksd: on|off|error <text>, from what run.sh did this start.
s=$(cat "${KT_TEST_ROOT:-}/data/nemesis/cabinwright/tweaks/coldstart-heat/last" 2>/dev/null)
case "$s" in
    heated) echo "on turned the heat on" ;;
    warm) echo "on warm enough, left the heat off" ;;
    "no reading") echo "on couldn't read the outside temperature" ;;
    failed*) echo "error the car didn't accept:${s#failed}" ;;
    *) echo "on heats the wheel and seats when it's cold" ;;
esac
