#!/system/bin/sh
# tweaksd: turns tweaks on and off as the Tweaks app (dev.cabinwright.tweaks) says: its own in
# ../tweaks/<id>/, and those of tweak packs, other NEMESIS packages with a tweaks/<id>/ folder
# (/data/nemesis/apps/<package>/tweaks/<id>/). An id belongs to the first package that has
# it, cabinwright.tweaks first and then by package id; a clash is logged and the later one skipped.
#
# Nothing a package leaves behind is stranded, and packages need no install hooks (NEMESIS
# runs a package's uninstall hooks on every update too, and they can't tell the two apart):
# - tweaksd keeps a copy of every tweak pack in $SHADOW, refreshed when its version changes.
#   When a pack has been gone for $DEPART_AFTER s with no NEMESIS install running, it was
#   removed rather than updated: its tweaks are turned off from that copy, then the copy goes.
#   Until then they are "pending" and left as they are. A pack's run.sh is restarted when the
#   pack's version changes, as it would still run the old script.
# - tweak.conf retired=1: the package no longer offers the tweak; it is turned off, and the
#   app hides it once it's off. A tweak that changes the system stays in its package as a
#   retired placeholder for good; only kind=service tweaks may simply be dropped.
# - replaces=<old id> (the app carries the old id's switch over to a renamed tweak) and
#   conflicts=<ids>: this tweak waits until those are off. Every round turns tweaks off
#   before it turns any on.
# - A tweak that can't be turned off any more (its files gone, no copy) stays in state.json
#   as "orphan" instead of being forgotten.
#
# The app is the only writer of the desired state; it serves it read-only at
# content://dev.cabinwright.tweaks.state/desired, rows "id=<id>, on=0|1, gen=<n>" (gen changes on
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
# Writes $DATA/state.json (world-readable; the app reads it) and a copy in /sdcard/cabinwright/tweaks.
# Tweak output goes to $DATA/logs/<id>.log.
#
# Moving from kia.tweaks (this package's name before 1.4), installed side by side for the switch:
# - while kia.tweaks' tweaksd runs, this one stands by: it runs no tweak script and reads no
#   switches, so two runners never drive the same tweaks. Its state.json is then kia.tweaks'
#   own, marked "standby".
# - with no data of its own yet, it imports kia.tweaks' (read only, never written): the switches
#   (want/, gen), state.json, the pack copies (shadow/), logs/, last/, skip-consent's pending
#   mark, and the skip-consent stock backup. Until it first acts the import follows
#   kia.tweaks' state; after that it never runs again ($DATA/imported says so).
# - once kia.tweaks is removed, its tweaks continue here: a removed package's tweak that
#   another installed package provides (this one's own, or a pack's) is never turned off.
#
# KT_TEST_ROOT, KT_TEST_PATH, KT_TEST_ROUNDS, KT_TEST_SLEEP: host tests only (tests/tweaksd-test.sh).
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 022   # NEMESIS starts services with umask 0
R=${KT_TEST_ROOT:-}
[ -n "$R" ] && PATH=$KT_TEST_PATH:$PATH
HERE=${0%/*}   # no dirname on the car
TWEAKS=${HERE%/*}/tweaks
DATA=$R/data/nemesis/cabinwright/tweaks
WANT=$DATA/want   # <id>: 1 or 0, as last read from the app
RUN=$DATA/run     # <id>.pid .state .text .since .error .failed .status .checked
INDEX=$DATA/index # <id>: the tweak's folder
PACKS=$R/data/nemesis/apps
SHADOW=$DATA/shadow   # <package>/: a copy of each tweak pack; <package>.missing: since when it's gone
DEPART_AFTER=60
LOGS=$DATA/logs
SD=/sdcard/cabinwright/tweaks
URI=content://dev.cabinwright.tweaks.state/desired
APP=dev.cabinwright.tweaks
FIRMWARE=$(getprop ro.build.product)
FAST=3          # seconds between rounds while the app is in the foreground
SLOW=15         # otherwise
REREAD=300      # re-read the app's state this often while it runs in the background
RECHECK=300     # oneshot status.sh can be slow (checksums), so it runs on changes and this often
RETRY=60        # wait before restarting a run.sh that died
LOG_MAX=32768
# kia.tweaks: its tweaksd's command line, its data and the skip-consent backup (all read only)
LEGACY_SVC=/data/nemesis/apps/kia.tweaks/svc/tweaksd.sh
LEGACY_DATA=$R/data/nemesis/kia-tweaks
LEGACY_BACKUP=$R/data/nemesis/backup/kia-tweaks.systemui
BACKUP=$R/data/nemesis/backup/cabinwright.tweaks.systemui
if [ -n "$R" ]; then FAST=${KT_TEST_SLEEP:-$FAST} SLOW=${KT_TEST_SLEEP:-$SLOW} DEPART_AFTER=${KT_TEST_DEPART_AFTER:-$DEPART_AFTER}; fi
CR=$(print '\r')

log() { print -r -- "$(date) $1"; }
# a line in the tweak's own log, and in ours
tlog() { print -r -- "$(date) tweaksd: $2" >> "$LOGS/$1.log"; log "$1: $2"; }

conf() {   # conf <id> <key> [default]
    local l v=$3 t
    read -r t < "$INDEX/$1"
    # a pending or orphaned tweak's folder is gone: its defaults
    [ -f "$t/tweak.conf" ] && while IFS= read -r l; do
        case "$l" in "$2="*) v=${l#*=}; break ;; esac
    done < "$t/tweak.conf"
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
# only when it changes: this is flash, and some values are re-put every round
put() {
    local v
    [ -f "$RUN/$1.$2" ] && IFS= read -r v < "$RUN/$1.$2" && [ "$v" = "$3" ] || print -r -- "$3" > "$RUN/$1.$2"
}

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
    local s t
    read -r t < "$INDEX/$1"
    [ -f "$t/status.sh" ] || { print "error no status.sh"; return; }
    s=$(sh "$t/status.sh" 2>/dev/null)
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
    [ -n "$p" ] && grep -q "/tweaks/$1/run.sh" /proc/$p/cmdline 2>/dev/null && print "$p"
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
    local t
    read -r t < "$INDEX/$1"
    rotate "$1"
    tlog "$1" "starting run.sh"
    sh "$t/run.sh" >> "$LOGS/$1.log" 2>&1 &
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
    local s st script rc t
    read -r t < "$INDEX/$1"
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
        sh "$t/$script.sh" >> "$LOGS/$1.log" 2>&1
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
    w=$(effective_want "$1")
    print -n "$(js "$1"):{\"want\":$(js "$([ "$w" = 1 ] && print on || { [ "$w" = 0 ] && print off; })")"
    print -n ",\"state\":$(js "$(get "$1" state)"),\"text\":$(js "$(get "$1" text)")"
    print -n ",\"last_change\":$(get "$1" since || print 0)"
    print -n ",\"name\":$(js "$(get "$1" name)"),\"pack\":$(js "$(get "$1" pack)")"
    [ -n "$(get "$1" departed)" ] && print -n ',"departed":true'
    [ -n "$(get "$1" pending)" ] && print -n ',"pending":true'
    [ -n "$(get "$1" orphan)" ] && print -n ',"orphan":true'

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
        for d in "$INDEX"/*; do
            [ -f "$d" ] || continue
            print -n "$sep"; tweak_json "${d##*/}"; sep=,
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

# the package a tweak folder belongs to
pkg_of() { local p=${1%/tweaks/*}; print -r -- "${p##*/}"; }

# a NEMESIS install or uninstall is running (an update removes the package for a moment)
nemesis_busy() {
    local f
    # cmdline separates arguments with NULs, which the shell can't hold: grep the file
    for f in $R/proc/[0-9]*/cmdline; do
        grep -q nemesis "$f" 2>/dev/null && grep -q install "$f" 2>/dev/null && return 0
    done
    return 1
}

version_of() {   # version= of a package folder's NEMESIS.data
    local l
    while IFS= read -r l; do case "$l" in version=*) print -r -- "${l#version=}"; return ;; esac; done \
        < "$1/NEMESIS.data" 2>/dev/null
}

# keeps $SHADOW in step with the installed packs; prints the folders of packs that have gone.
# Its output is a list of folders to act on, so its log lines go to stderr (our log).
shadow_packs() {
    local d p now
    now=$(date +%s)
    for d in "$PACKS"/*/; do
        d=${d%/}; p=${d##*/}
        [ "$d" = "${TWEAKS%/tweaks}" ] && continue
        ls "$d/tweaks/"*/tweak.conf >/dev/null 2>&1 || continue
        [ -f "$SHADOW/$p.missing" ] && { rm -f "$SHADOW/$p.missing"; log "$p is back" >&2; }
        [ -d "$SHADOW/$p" ] && [ "$(version_of "$SHADOW/$p")" = "$(version_of "$d")" ] && continue
        # not while NEMESIS may still be writing it: a half copy would never be refreshed
        nemesis_busy && continue
        rm -rf "$SHADOW/$p.tmp"
        cp -R "$d" "$SHADOW/$p.tmp" && rm -rf "$SHADOW/$p" && mv "$SHADOW/$p.tmp" "$SHADOW/$p" \
            && log "kept a copy of $p $(version_of "$d")" >&2
    done
    for d in "$SHADOW"/*/; do
        d=${d%/}; p=${d##*/}
        case "$p" in *.tmp) rm -rf "$d"; continue ;; esac
        [ -d "$PACKS/$p" ] && continue
        [ -f "$SHADOW/$p.missing" ] || { print "$now" > "$SHADOW/$p.missing"; log "$p is gone; turning its tweaks off in ${DEPART_AFTER}s unless it comes back" >&2; }
        nemesis_busy && print "$now" > "$SHADOW/$p.missing"
        [ $((now - $(cat "$SHADOW/$p.missing"))) -ge $DEPART_AFTER ] && print -r -- "$d"
    done
}

# the switch position tweaksd acts on: the app's, except that a retired tweak or one whose
# pack was removed is off whatever the switch says
effective_want() {
    if [ "$(conf "$1" retired 0)" = 1 ] || [ -n "$(get "$1" departed)" ]; then print 0
    else cat "$WANT/$1" 2>/dev/null; fi
}

# conflicts= and replaces= list tweaks that must be off before this one turns on, either way
# round: a tweak that is on also keeps off those that it lists. Sets BLOCKER to the first
# one in the way.
clear_of_conflicts() {
    local c f l
    BLOCKER=
    l="$(conf "$1" conflicts) $(conf "$1" replaces)"
    set -f
    for c in ${l//,/ }; do
        [ -f "$INDEX/$c" ] || continue
        case "$(get "$c" state)" in on|working|error) set +f; BLOCKER=$c; break ;; esac
    done
    set +f
    [ -z "$BLOCKER" ] && for f in "$INDEX"/*; do
        c=${f##*/}
        [ "$c" != "$1" ] || continue
        case "$(get "$c" state)" in on|working|error) ;; *) continue ;; esac
        l="$(conf "$c" conflicts) $(conf "$c" replaces)"
        case " ${l//,/ } " in *" $1 "*) BLOCKER=$c; break ;; esac
    done
    [ -z "$BLOCKER" ] && return 0
    l=$(get "$BLOCKER" name)
    BLOCKER=${l:-$BLOCKER}
    return 1
}

# rebuilds $INDEX: every tweak folder of cabinwright.tweaks and the installed tweak packs, then the
# tweaks of removed packs (from their copies, marked departed) until they are off.
index_tweaks() {
    local d id own seen= f gone p v
    # only ever folders inside $SHADOW: these get deleted below
    gone=
    for p in $(shadow_packs); do
        case "$p" in "$SHADOW"/[a-z0-9]*) [ -d "$p" ] && gone="$gone $p" ;; *) log "ignored odd pack folder: $p" ;; esac
    done
    for d in "$TWEAKS"/*/ "$PACKS"/*/tweaks/*/ $(for p in $gone; do print "$p/tweaks/*/"; done); do
        [ -f "$d/tweak.conf" ] || continue
        d=${d%/}; id=${d##*/}
        case "$id" in ""|*[!a-z0-9-]*) continue ;; esac
        case " $seen " in
            *" $id "*)
                # a removed package's tweak that an installed package provides too isn't
                # departed: it continues from that package and stays as it is
                case "$d" in
                    "$SHADOW"/*) [ "$(get "$id" continues)" = "$(pkg_of "$d")" ] || {
                        put "$id" continues "$(pkg_of "$d")"
                        log "$id: $(pkg_of "$d") was removed; $id continues from $(get "$id" pack)"; } ;;
                    *) [ "$(pkg_of "$d")" = "$(pkg_of "$TWEAKS/x")" ] || \
                        [ -n "$(get "$id" clash)" ] || { put "$id" clash 1; log "$id: also in $(pkg_of "$d"), skipped"; } ;;
                esac
                continue ;;
        esac
        seen="$seen $id"
        for f in orphan pending departed; do [ -f "$RUN/$id.$f" ] && rm -f "$RUN/$id.$f"; done
        case "$d" in "$SHADOW"/*) put "$id" departed 1 ;; esac
        put "$id" pack "$(pkg_of "$d")"
        own=
        [ -f "$INDEX/$id" ] && read -r own < "$INDEX/$id"
        [ "$own" = "$d" ] || { print -r -- "$d" > "$INDEX/$id"; log "$id: from $d"; }
        put "$id" name "$(conf "$id" name "$id")"
        # an updated pack's run.sh still runs the old script: start it over, at once (not
        # after $RETRY, which would let a tweak it conflicts with turn on meanwhile)
        v=$(version_of "${d%/tweaks/*}")
        if [ "$(get "$id" ver)" != "$v" ]; then
            [ -n "$(get "$id" ver)" ] && [ -n "$(running "$id")" ] && {
                tlog "$id" "$(pkg_of "$d") is now $v; restarting run.sh"; stop_service "$id"; rm -f "$RUN/$id.started"; }
            put "$id" ver "$v"
        fi
    done
    for f in "$INDEX"/*; do
        [ -f "$f" ] || continue
        id=${f##*/}
        case " $seen " in *" $id "*) continue ;; esac
        [ -n "$(get "$id" orphan)" ] && continue
        # its pack has a copy: it was removed or is being updated; wait for shadow_packs to tell
        if [ -d "$SHADOW/$(get "$id" pack)" ]; then
            [ -n "$(get "$id" pending)" ] || { put "$id" pending 1; put "$id" text "its package is gone; waiting to see if it comes back"; }
            continue
        fi
        [ -n "$(running "$id")" ] && stop_service "$id"
        if [ "$(get "$id" kind)" = oneshot ] && case "$(get "$id" state)" in on|working|error) ;; *) false ;; esac; then
            # its files went without a copy to turn it off with: say so rather than forget it
            put "$id" orphan 1
            set_state "$id" error "left on: $(get "$id" pack) was removed and it can't be turned off from here"
        else
            rm -f "$f" "$RUN/$id".*
            log "$id: its package is gone"
        fi
    done
    # a removed pack whose tweaks are all off (or never applied here), or continue from another
    # package: drop its copy
    for p in $gone; do
        for d in "$p"/tweaks/*/; do
            d=${d%/}; id=${d##*/}
            f=
            [ -f "$INDEX/$id" ] && read -r f < "$INDEX/$id"
            [ "$f" = "$d" ] || continue   # not run from this copy
            case "$(get "$id" state)" in on|working|error) continue 2 ;; esac
        done
        # its tweaks go with it, so they aren't run from the copy's folder once it's gone
        for d in "$p"/tweaks/*/; do
            d=${d%/}; id=${d##*/}
            [ "$(get "$id" continues)" = "${p##*/}" ] && rm -f "$RUN/$id.continues"
            [ -f "$INDEX/$id" ] && read -r f < "$INDEX/$id" && [ "$f" = "$d" ] && rm -f "$INDEX/$id" "$RUN/$id".*
        done
        case "$p" in "$SHADOW"/[a-z0-9]*) rm -rf "$p" "$p.missing" ;; esac
        log "${p##*/}: removed; its tweaks are off or continue from another package"
    done
}

stop_all() {
    local f id
    for f in "$RUN"/*.pid; do
        [ -f "$f" ] || continue
        id=${f##*/}; id=${id%.pid}
        stop_service "$id"
    done
}

# ---- moving from kia.tweaks

# kia.tweaks' tweaksd is running (its command line names its script)
legacy_running() {
    local f
    for f in $R/proc/[0-9]*/cmdline; do
        grep -q "$LEGACY_SVC" "$f" 2>/dev/null && return 0
    done
    return 1
}

# copy_new <from> <to>: a copy of a file or folder where there is none yet
copy_new() {
    [ -e "$1" ] && [ ! -e "$2" ] || return 0
    rm -rf "$2.tmp"
    cp -R "$1" "$2.tmp" && mv "$2.tmp" "$2"
}

# Imports kia.tweaks' data (read only) while this tweaksd has none of its own. $DATA/imported
# holds "started" during the first import, then the `ls -l` of the kia.tweaks state.json it
# last followed, and "final" once this tweaksd has acted: after that it never imports again.
import_legacy() {
    local m st f first=
    [ -d "$LEGACY_DATA" ] || return 0
    m=$(cat "$DATA/imported" 2>/dev/null)
    [ "$m" = final ] && return 0
    # our own state without an import mark: this tweaksd ran before, nothing to import
    [ -z "$m" ] && [ -f "$DATA/state.json" ] && return 0
    st=$(ls -l "$LEGACY_DATA/state.json" 2>/dev/null)
    case "$m" in "") first=1 ;; started) first=1 ;; "$st") return 0 ;; esac
    [ -n "$first" ] && print started > "$DATA/imported"
    # the switches as kia.tweaks' tweaksd last read them, and their generation
    if [ -d "$LEGACY_DATA/want" ]; then
        rm -rf "$WANT.tmp"
        cp -R "$LEGACY_DATA/want" "$WANT.tmp" && rm -rf "$WANT" && mv "$WANT.tmp" "$WANT" && chmod 700 "$WANT"
    fi
    [ -f "$LEGACY_DATA/gen" ] && cp "$LEGACY_DATA/gen" "$DATA/gen"
    [ -f "$LEGACY_DATA/skip-consent.pending" ] && cp "$LEGACY_DATA/skip-consent.pending" "$DATA/skip-consent.pending"
    if [ -n "$first" ]; then
        # the copies of the packs (so a pack removed meanwhile is still turned off), logs,
        # the service tweaks' last actions, and skip-consent's stock SystemUI backup
        # (not kia.tweaks' copy of this package, which it took for a pack, or of itself)
        for f in "$LEGACY_DATA"/shadow/*; do
            case "${f##*/}" in "$(pkg_of "$TWEAKS/x")"|"$(pkg_of "$TWEAKS/x")".*|kia.tweaks|kia.tweaks.*) continue ;; esac
            [ -e "$f" ] && copy_new "$f" "$SHADOW/${f##*/}"
        done
        for f in "$LEGACY_DATA"/logs/*; do
            [ -f "$f" ] && copy_new "$f" "$LOGS/${f##*/}"
        done
        copy_new "$LEGACY_DATA/last" "$DATA/last"
        copy_new "$LEGACY_BACKUP" "$BACKUP" && [ -d "$BACKUP" ] && log "skip-consent backup: $BACKUP (copied from $LEGACY_BACKUP)"
    fi
    [ -f "$LEGACY_DATA/state.json" ] && [ ! -f "$DATA/state.json" ] && standby_state
    print -r -- "${st:-none}" > "$DATA/imported"
    if [ -n "$first" ]; then
        log "imported kia.tweaks' data from $LEGACY_DATA (read only): switches $(ls "$WANT" | while read -r f; do print -n "$f=$(cat "$WANT/$f") "; done)"
    fi
}

# this tweaksd acts from now on: a last import, then never again
finish_import() {
    local m
    m=$(cat "$DATA/imported" 2>/dev/null)
    [ -n "$m" ] && [ "$m" != final ] || return 0
    import_legacy
    print final > "$DATA/imported"
    log "import from kia.tweaks done; running the tweaks from here"
}

# while standing by: kia.tweaks' state.json (root's, one line) is ours, marked "standby"
standby_state() {
    local s
    if [ -f "$LEGACY_DATA/state.json" ]; then
        IFS= read -r s < "$LEGACY_DATA/state.json"
    fi
    case "$s" in "{"*) ;; *) s="{\"time\":$(date +%s),\"tweaks\":{}}" ;; esac
    print -r -- "{\"standby\":\"kia.tweaks\",${s#\{}" > $DATA/state.json.tmp
    chmod 644 $DATA/state.json.tmp
    mv $DATA/state.json.tmp $DATA/state.json
}

# ends a round: the test hook, then sleep in the background so a stop signal is handled at once
pause() {
    ROUND=$((ROUND + 1))
    if [ -n "$KT_TEST_ROUNDS" ] && [ $ROUND -ge "$KT_TEST_ROUNDS" ]; then stop_all; exit 0; fi
    sleep $1 &
    wait $!
}

# ---- main

cd $DATA 2>/dev/null || cd /
mkdir -p $WANT $RUN $LOGS $INDEX $SHADOW
cd $DATA
# /data/nemesis/cabinwright is shared with the other Cabinwright packages (the store)
chmod 755 ${DATA%/*} $DATA
chmod 700 $WANT $RUN $LOGS $INDEX $SHADOW
log "starting (firmware $FIRMWARE)"
# a run.sh left over from before an update runs the old script: restart it
stop_all
trap 'log "stopping"; stop_all; exit 0' TERM INT HUP

# NEMESIS can restart this service a moment before an update has replaced its files, which
# leaves the old script running: when the file changes, start over with the new one
SELF=$(ls -l "$0")

import_legacy
LAST_READ=0 LAST_PROC= APP_READ= STANDBY= ROUND=0
while :; do
    if [ "$(ls -l "$0" 2>/dev/null)" != "$SELF" ] && [ -f "$0" ]; then
        log "tweaksd.sh changed; restarting with the new one"
        stop_all
        exec sh "$0"
    fi
    # two runners must never drive the same tweaks: while kia.tweaks' tweaksd runs, stand by
    if legacy_running; then
        if [ -z "$STANDBY" ]; then
            log "kia.tweaks' tweaksd is running ($LEGACY_SVC): standing by until it stops"
            stop_all
            STANDBY=1
        fi
        import_legacy
        standby_state
        pause $SLOW
        continue
    fi
    [ -n "$STANDBY" ] && log "kia.tweaks' tweaksd has stopped; taking over"
    STANDBY=
    finish_import
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

    index_tweaks
    # turning off comes first, so a tweak that replaces or conflicts with another never
    # runs alongside it: pass 1 handles everything that should be off, pass 2 the rest
    for pass in off on; do
        for d in "$INDEX"/*; do
            [ -f "$d" ] || continue
            id=${d##*/}
            [ -n "$(get "$id" orphan)" ] || [ -n "$(get "$id" pending)" ] && continue
            put "$id" kind "$(conf "$id" kind service)"
            if ! supported "$id"; then
                [ $pass = off ] || continue
                [ -n "$(running "$id")" ] && stop_service "$id"
                set_state "$id" unsupported "made for other head unit software"
                continue
            fi
            want=$(effective_want "$id")
            case "$pass:$want" in off:1|on:0|on:) continue ;; esac
            if [ "$want" = 1 ] && case "$(get "$id" state)" in on|working|error) false ;; esac \
                    && ! clear_of_conflicts "$id"; then
                set_state "$id" off "waiting for $BLOCKER to turn off"
                continue
            fi
            case "$(get "$id" kind)" in
                service)
                    # nothing known yet: leave it as it is
                    if [ -n "$want" ]; then do_service "$id" "$want"
                    else set_state "$id" off "waiting for the Tweaks app"; fi ;;
                oneshot) do_oneshot "$id" "$want" "$CHANGED" ;;
                *) set_state "$id" error "unknown kind in tweak.conf" ;;
            esac
        done
    done
    write_state
    [ "${proc#* }" = fg ] && n=$FAST || n=$SLOW
    pause $n
done
