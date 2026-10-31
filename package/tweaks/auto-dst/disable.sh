#!/system/bin/sh
# Turning auto-dst off stops following the schedule and leaves the clock as it is: the
# head unit's own daylight-saving switch (TimePolicyService's setDst) keeps its current
# value, as if the driver had set it by hand. Putting back the value from before the tweak
# was turned on would move the clock by an hour for no reason the driver can see. The clock
# settings' checkbox (summer_time) stays with it, so it keeps matching the clock.
kt keep setting:system/summer_time
echo "$(date) stopped following daylight saving time; the clock stays as it is"
