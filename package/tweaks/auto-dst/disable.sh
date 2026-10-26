#!/system/bin/sh
# Turning auto-dst off stops following the schedule and leaves the clock as it is: the
# head unit's own daylight-saving switch (TimePolicyService's setDst) keeps its current
# value, as if the driver had set it by hand. Putting back the value from before the tweak
# was turned on would move the clock by an hour for no reason the driver can see, so this
# changes nothing. The runner then restores Settings.System summer_time from its journal,
# so the clock settings' checkbox can show the earlier value until the switch is next set.
echo "$(date) stopped following daylight saving time; the clock stays as it is"
