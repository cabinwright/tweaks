#!/system/bin/sh
# One line for the runner: on|off|error <text>, from what run.sh did this start.
s=$(cat "$TWEAK_DATA/last" 2>/dev/null)
case "$s" in
    heated) echo "on turned the heat on" ;;
    warm) echo "on warm enough, left the heat off" ;;
    "no reading") echo "on couldn't read the outside temperature" ;;
    failed*) echo "error the car didn't accept:${s#failed}" ;;
    *) echo "on heats the wheel and seat when it's cold" ;;
esac
