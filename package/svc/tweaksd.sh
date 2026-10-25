#!/system/bin/sh
# tweaksd: turns the tweaks in ../tweaks/<id>/ on and off as the Tweaks app (dev.kiatweaks) says.
#
# The app is the only writer of the desired state; it serves it read-only at
# content://dev.kiatweaks.state/desired, rows "id=<id>, on=0|1, gen=<n>" (gen changes on
# every switch). Reading through the provider rather than a file means no other app can flip
# a tweak: the provider only answers uid 0/1000/2000 and the app itself.
#
# A tweak folder: tweak.conf (name=, summary=, description=, firmware= exact
# ro.build.product strings or *, kind=service|oneshot, default=, risk=normal|system),
# status.sh (one line "on|off|error <text>"), and run.sh (kind=service, kept running while
# on) or enable.sh / disable.sh (kind=oneshot, idempotent, exit 0 = done).
#
# Each `content query` starts a VM (about 0.7 s of CPU on this head unit), and the desired
# state can only change while the app runs, so it is read every FAST s while the app is in
# the foreground, once more after it leaves, every REREAD s while it is in the background,
# and not at all while it isn't running. The last state read is kept in $WANT, so tweaks
# come back at boot before the app is up.
#
# Writes $DATA/state.json (world-readable; the app reads it) and a copy in /sdcard/kia-tweaks.
# Tweak output goes to $DATA/logs/<id>.log.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 022   # NEMESIS starts services with umask 0
HERE=${0%/*}   # no dirname on the car
TWEAKS=${HERE%/*}/tweaks
DATA=/data/nemesis/kia-tweaks
WANT=$DATA/want   # <id>: 1 or 0, as last read from the app
RUN=$DATA/run     # <id>.pid .state .text .since .error .failed .status .checked
LOGS=$DATA/logs
SD=/sdcard/kia-tweaks
URI=content://dev.kiatweaks.state/desired
APP=dev.kiatweaks
FIRMWARE=$(getprop ro.build.product)
FAST=3          # seconds between rounds while the app is in the foreground
SLOW=15         # otherwise
REREAD=300      # re-read the app's state this often while it runs in the background
RECHECK=300     # oneshot status.sh can be slow (checksums), so it runs on changes and this often
RETRY=60        # wait before restarting a run.sh that died
LOG_MAX=32768
CR=$(print '\r')

log() { print -r -- "$(date) $1"; }
# a line in the tweak's own log, and in ours
tlog() { print -r -- "$(date) tweaksd: $2" >> "$LOGS/$1.log"; log "$1: $2"; }

conf() {   # conf <id> <key> [default]
    local l v=$3
    while IFS= read -r l; do
        case "$l" in "$2="*) v=${l#*=}; break ;; esac
    done < "$TWEAKS/$1/tweak.conf"
    print -r -- "$v"
}

supported() {
    local f fw
    fw=$(conf "$1" firmware '*')
    [ "$fw" = '*' ] && return 0
    set -f
    for f in ${fw//,/ }; do
        [ "$f" = "$FIRMWARE" ] && { set +f; return 0; }
    done
    set +f
    return 1
}

get() { cat "$RUN/$1.$2" 2>/dev/null; }
put() { print -r -- "$3" > "$RUN/$1.$2"; }

# state: on, off, error, working or unsupported; the time of the last change is kept
set_state() {
    if [ "$(get "$1" state)" != "$2" ]; then
        put "$1" since "$(date +%s)"
        put "$1" state "$2"
        tlog "$1" "now $2${3:+ ($3)}"
    fi
    put "$1" text "$3"
}

set_error() {
    put "$1" error "$(date +%s) $2"
    tlog "$1" "$2"
}

# the text after status.sh's first word
text_of() { case "$1" in *" "*) print -r -- "${1#* }" ;; esac; }

# status.sh's line as "state text"; a missing or broken script is an error
status_of() {
    local s
    [ -f "$TWEAKS/$1/status.sh" ] || { print "error no status.sh"; return; }
    s=$(sh "$TWEAKS/$1/status.sh" 2>/dev/null)
    s=${s%%$CR*}
    case "$s" in
        on|off|error) print -r -- "$s" ;;
        "on "*|"off "*|"error "*) print -r -- "$s" ;;
        *) print -r -- "error status.sh said: ${s:-nothing}" ;;
    esac
}

rotate() {
    local p u g size rest
    ls -l "$LOGS/$1.log" 2>/dev/null | read -r p u g size rest
    [ "${size:-0}" -gt $LOG_MAX ] 2>/dev/null && mv "$LOGS/$1.log" "$LOGS/$1.log.1"
}

# ---- kind=service

running() {   # pid of the tweak's run.sh while it is alive
    local p
    p=$(get "$1" pid)
    [ -n "$p" ] && grep -q "tweaks/$1/run.sh" /proc/$p/cmdline 2>/dev/null && print "$p"
}

children() {
    local u p pp rest
    ps | while read -r u p pp rest; do [ "$pp" = "$1" ] && print "$p"; done
}

# run.sh's own children (sleep, logcat, ...) would outlive it, so take them down too
kill_tree() {
    local c kids
    kids=$(children "$1")
    kill "$1" 2>/dev/null
    for c in $kids; do kill_tree "$c"; done
}

start_service() {
    rotate "$1"
    tlog "$1" "starting run.sh"
    sh "$TWEAKS/$1/run.sh" >> "$LOGS/$1.log" 2>&1 &
    put "$1" pid $!
    put "$1" started "$(date +%s)"
}

stop_service() {
    local p
    p=$(running "$1")
    [ -n "$p" ] && { kill_tree "$p"; tlog "$1" "stopped run.sh"; }
    rm -f "$RUN/$1.pid"
}

do_service() {   # <id> <want>
    local p s now
    p=$(running "$1")
    now=$(date +%s)
    if [ "$2" = 1 ] && [ -z "$p" ]; then
        if [ -f "$RUN/$1.pid" ]; then
            # it was started and has died since
            rm -f "$RUN/$1.pid"
            set_error "$1" "run.sh stopped on its own"
        fi
        if [ $((now - $(get "$1" started || print 0))) -ge $RETRY ]; then
            start_service "$1"
            p=$(get "$1" pid)
        fi
    elif [ "$2" = 0 ] && [ -n "$p" ]; then
        stop_service "$1"
        p=
    fi
    s=$(status_of "$1")
    case "$s" in
        error*) set_state "$1" error "$(text_of "$s")" ;;
        *) [ -n "$p" ] && set_state "$1" on "$(text_of "$s")" || set_state "$1" off "$(text_of "$s")" ;;
    esac
}

# ---- kind=oneshot

do_oneshot() {   # <id> <want> <recheck: 1 to run status.sh now>
    local s st script rc
    s=$(get "$1" status)
    if [ "$3" = 1 ] || [ -z "$s" ] || [ $(($(date +%s) - $(get "$1" checked || print 0))) -ge $RECHECK ]; then
        s=$(status_of "$1")
        put "$1" status "$s"
        put "$1" checked "$(date +%s)"
    fi
    st=${s%% *}
    # only from the opposite state: "error" means leave it alone
    if [ "$2" = 1 ] && [ "$st" = off ]; then script=enable
    elif [ "$2" = 0 ] && [ "$st" = on ]; then script=disable
    fi
    # a failed script isn't run again until the switch changes
    if [ -n "$script" ] && [ "$(get "$1" failed)" != "$2" ]; then
        set_state "$1" working "running $script.sh"
        write_state
        rotate "$1"
        tlog "$1" "running $script.sh"
        sh "$TWEAKS/$1/$script.sh" >> "$LOGS/$1.log" 2>&1
        rc=$?
        s=$(status_of "$1")
        put "$1" status "$s"
        put "$1" checked "$(date +%s)"
        st=${s%% *}
        if [ $rc != 0 ]; then
            put "$1" failed "$2"
            set_error "$1" "$script.sh failed (exit $rc)"
        elif [ "$st" != "$([ "$2" = 1 ] && print on || print off)" ]; then
            put "$1" failed "$2"
            set_error "$1" "$script.sh finished but the tweak is still $st"
        else
            rm -f "$RUN/$1.failed"
            tlog "$1" "$script.sh done"
        fi
    fi
    case "$st" in
        on|off|error) set_state "$1" "$st" "$(text_of "$s")" ;;
        *) set_state "$1" error "status.sh said: $s" ;;
    esac
}

# ---- the app

app_proc() {   # "<pid> <fg|bg>" while the app runs
    local u p pp vs rss pcy rest
    ps -P | while read -r u p pp vs rss pcy rest; do
        case "$rest" in *" $APP") print "$p $pcy"; break ;; esac
    done
}

# reads the switches into $WANT; returns 1 if the app's provider didn't answer
read_desired() {
    local out gen l id on
    out=$(content query --uri $URI 2>&1)
    case "$out" in
        *"Row: "*) ;;
        "No result found."*) return 0 ;;   # the app has nothing to say about any tweak yet
        *) return 1 ;;
    esac
    print -r -- "$out" | while IFS= read -r l; do
        case "$l" in "Row: "*) ;; *) continue ;; esac
        id=${l#*id=}; id=${id%%,*}
        on=${l#*on=}; on=${on%%,*}
        case "$id" in ""|*[!a-z0-9-]*) continue ;; esac
        case "$on" in 0|1) ;; *) continue ;; esac
        # a new switch position also means a failed script may be tried again
        [ "$(cat "$WANT/$id" 2>/dev/null)" = "$on" ] || { print "$on" > "$WANT/$id"; rm -f "$RUN/$id.failed"; }
    done
    gen=${out##*gen=}; gen=${gen%%[!0-9]*}
    if [ "$gen" != "$(cat $DATA/gen 2>/dev/null)" ]; then
        print "$gen" > $DATA/gen
        CHANGED=1
    fi
    return 0
}

# ---- state.json

js() {   # a JSON string
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//	/ }
    s=${s//$CR/}
    print -rn -- "\"$s\""
}

# the last few lines of the tweak's log, as a JSON array
log_tail() {
    local l a b c d e sep=
    [ -f "$LOGS/$1.log" ] || { print -n '[]'; return; }
    while IFS= read -r l; do a=$b; b=$c; c=$d; d=$e; e=$l; done < "$LOGS/$1.log"
    print -n '['
    for l in "$a" "$b" "$c" "$d" "$e"; do
        [ -n "$l" ] || continue
        print -n "$sep"; js "$l"; sep=,
    done
    print -n ']'
}

tweak_json() {
    local e w
    e=$(get "$1" error)
    w=$(cat "$WANT/$1" 2>/dev/null)
    print -n "$(js "$1"):{\"want\":$(js "$([ "$w" = 1 ] && print on || { [ "$w" = 0 ] && print off; })")"
    print -n ",\"state\":$(js "$(get "$1" state)"),\"text\":$(js "$(get "$1" text)")"
    print -n ",\"last_change\":$(get "$1" since || print 0)"
    # the script for the current switch position failed: it waits for the next change
    [ -n "$w" ] && [ "$(get "$1" failed)" = "$w" ] && print -n ',"failed":true' || print -n ',"failed":false'
    print -n ",\"last_error\":$(js "${e#* }"),\"last_error_time\":${e%% *}"
    [ -n "$e" ] || print -n 0
    print -n ",\"log\":$(log_tail "$1")}"
}

LAST_BODY=
write_state() {
    local d id sep= body
    body=$(
        print -n "\"pid\":$$,\"firmware\":$(js "$FIRMWARE"),\"app_seen\":$( [ -n "$APP_READ" ] && print true || print false),\"tweaks\":{"
        for d in "$TWEAKS"/*/; do
            id=${d%/}; id=${id##*/}
            [ -f "$d/tweak.conf" ] || continue
            print -n "$sep"; tweak_json "$id"; sep=,
        done
        print -n '}'
    )
    print -r -- "{\"time\":$(date +%s),$body}" > $DATA/state.json.tmp
    chmod 644 $DATA/state.json.tmp
    mv $DATA/state.json.tmp $DATA/state.json
    # the sdcard copy only when something changed (it is flash). Root here lacks
    # CAP_DAC_OVERRIDE and the sdcard sits behind /mnt/shell (shell's, mode 700): copy as shell.
    if [ "$body" != "$LAST_BODY" ]; then
        nemesis root 2000 -c "mkdir -p $SD && cp $DATA/state.json $SD/state.json.tmp && mv $SD/state.json.tmp $SD/state.json" \
            >/dev/null 2>&1
        LAST_BODY=$body
    fi
}

stop_all() {
    local f id
    for f in "$RUN"/*.pid; do
        [ -f "$f" ] || continue
        id=${f##*/}; id=${id%.pid}
        stop_service "$id"
    done
}

# ---- main

mkdir -p $WANT $RUN $LOGS
chmod 755 $DATA
chmod 700 $WANT $RUN $LOGS
log "starting (firmware $FIRMWARE)"
# a run.sh left over from before an update runs the old script: restart it
stop_all
trap 'log "stopping"; stop_all; exit 0' TERM INT HUP

LAST_READ=0 LAST_PROC= APP_READ=
while :; do
    now=$(date +%s)
    proc=$(app_proc)
    CHANGED=
    # read when the app is in front, has just left it, has (re)started, or now and then
    if [ "${proc#* }" = fg ] || [ "${LAST_PROC#* }" = fg ] || { [ -n "$proc" ] && [ "${proc% *}" != "${LAST_PROC% *}" ]; } \
            || { [ -n "$proc" ] && [ $((now - LAST_READ)) -ge $REREAD ]; } || [ -z "$(ls $WANT)" ]; then
        if read_desired; then
            [ -n "$APP_READ" ] || log "reading switches from the Tweaks app"
            APP_READ=1 LAST_READ=$now
        else
            [ -z "$APP_READ" ] || log "the Tweaks app didn't answer"
            APP_READ=
        fi
    fi
    LAST_PROC=$proc
    [ -n "$CHANGED" ] && log "switches changed"

    for d in "$TWEAKS"/*/; do
        id=${d%/}; id=${id##*/}
        [ -f "$d/tweak.conf" ] || continue
        if ! supported "$id"; then
            [ -n "$(running "$id")" ] && stop_service "$id"
            set_state "$id" unsupported "made for other head unit software"
            continue
        fi
        want=$(cat "$WANT/$id" 2>/dev/null)
        case "$(conf "$id" kind service)" in
            service)
                # nothing known yet: leave it as it is
                if [ -n "$want" ]; then do_service "$id" "$want"
                else set_state "$id" off "waiting for the Tweaks app"; fi ;;
            oneshot) do_oneshot "$id" "$want" "$CHANGED" ;;
            *) set_state "$id" error "unknown kind in tweak.conf" ;;
        esac
    done
    write_state
    [ "${proc#* }" = fg ] && n=$FAST || n=$SLOW
    # sleep in the background so a stop signal is handled at once
    sleep $n &
    wait $!
done
