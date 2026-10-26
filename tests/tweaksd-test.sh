#!/bin/sh
# Host test for tweaksd: runs package/svc/tweaksd.sh against a mock head unit (a root with
# /data/nemesis, /proc command lines and stub getprop/content/ps/nemesis), with fixture tweaks
# whose scripts log every enable/disable. Covers the move from kia.tweaks (this package's name
# before 1.4) and the departure rules:
#   A. while kia.tweaks' tweaksd runs: stand by (no script runs, nothing indexed), import its
#      data read only (switches, state, shadow/, logs, last/, pending mark, skip-consent
#      backup), and follow its switches while standing by
#   B. once it stops: take over with the imported switches; nothing is turned off; the import
#      is final and never redone, whatever kia.tweaks' files say later
#   C. kia.tweaks removed after this tweaksd kept a copy of it: its tweaks (the same ids as
#      ours) are not departed and not turned off; the copy goes
#   D. a removed pack's tweak that another installed pack provides continues from that pack
#   E. control: a removed pack's own tweak is still turned off from its copy
#
# usage: tests/tweaksd-test.sh      (KT_SH picks the shell: default mksh, else bash with a
#                                    `print` stand-in for mksh's builtin)
# check '<test>' runs its single-quoted test later, on purpose; a && ok || bad is fine here
# shellcheck disable=SC2016,SC2015
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap '[ -n "$KEEP" ] && echo "kept $W" || rm -rf "$W"' EXIT
FAILS=0
SH=${KT_SH:-$(command -v mksh || command -v bash)}
case "$SH" in
    *bash)
        # mksh's print, as far as tweaksd uses it: -r (no escapes), -n (no newline), --
        cat > "$W/print.sh" <<'EOF'
print() {
    local raw= nl=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --) shift; break ;;
            -r) raw=1; shift ;;
            -n) nl=; shift ;;
            -rn|-nr) raw=1; nl=; shift ;;
            *) break ;;
        esac
    done
    if [ -n "$raw" ]; then printf '%s' "$*"; else printf '%b' "$*"; fi
    if [ -n "$nl" ]; then printf '\n'; fi
    return 0
}
EOF
        export BASH_ENV="$W/print.sh" ;;
esac

M=$W/root
A=$M/data/nemesis/apps
DATA=$M/data/nemesis/cabinwright/tweaks
OLD=$M/data/nemesis/kia-tweaks
ACT=$M/actions.log

mkdir -p "$W/stubs"
cat > "$W/stubs/getprop" <<'EOF'
#!/bin/sh
[ "$1" = ro.build.product ] && echo TESTFW
exit 0
EOF
cat > "$W/stubs/content" <<'EOF'
#!/bin/sh
cat "$KT_TEST_ROOT/content.out" 2>/dev/null || echo "No result found."
EOF
cat > "$W/stubs/ps" <<'EOF'
#!/bin/sh
echo "USER     PID   PPID  VSIZE  RSS   PCY  WCHAN    PC         NAME"
EOF
cat > "$W/stubs/nemesis" <<'EOF'
#!/bin/sh
echo "nemesis $*" >> "$KT_TEST_ROOT/nemesis.log"
EOF
chmod 755 "$W"/stubs/*
export KT_TEST_ROOT="$M" KT_TEST_PATH="$W/stubs:/usr/bin:/bin:/usr/sbin:/sbin" KT_TEST_SLEEP=0

ok() { echo "  ok: $1"; }
bad() { echo "  FAILED: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

# tweak <package dir> <id> <kind> [tweak.conf lines]: a fixture tweak. Its state is
# $M/car/<id> (on/off); enable.sh and disable.sh log "<enable|disable> <package> <id>"
tweak() {
    d=$1/tweaks/$2
    mkdir -p "$d"
    printf 'name=%s\nkind=%s\nfirmware=*\n%s' "$2" "$3" "${4:-}" > "$d/tweak.conf"
    cat > "$d/status.sh" <<EOF
s=\$(cat "\$KT_TEST_ROOT/car/$2" 2>/dev/null)
echo "\${s:-off} fixture"
EOF
    for op in enable disable; do
        st=on; [ $op = disable ] && st=off
        cat > "$d/$op.sh" <<EOF
p=\${0%/tweaks/*}; echo "$op \${p##*/} $2" >> "\$KT_TEST_ROOT/actions.log"
mkdir -p "\$KT_TEST_ROOT/car"; echo $st > "\$KT_TEST_ROOT/car/$2"
EOF
    done
    if [ "$3" = service ]; then printf 'sleep 2\n' > "$d/run.sh"; fi
}
package() {   # package <id> <version>
    mkdir -p "$A/$1"
    printf '[nemesis]\nid=%s\nversion=%s\nname=%s\ntypes=application\n' "$1" "$2" "$1" > "$A/$1/NEMESIS.data"
}
car() { mkdir -p "$M/car"; echo "$2" > "$M/car/$1"; }
snapshot() { (cd "$1" 2>/dev/null && find . -type f | sort | while read -r f; do cksum "$f"; done); }
tweaksd() {   # tweaksd <rounds>; kia.tweaks' files must come out of every run as they went in
    snapshot "$OLD" > "$W/old.before"
    snapshot "$M/data/nemesis/backup/kia-tweaks.systemui" > "$W/backup.before"
    KT_TEST_ROUNDS=$1 "$SH" "$A/cabinwright.tweaks/svc/tweaksd.sh" >> "$W/tweaksd.log" 2>&1 || bad "tweaksd exited with $?"
    snapshot "$OLD" | diff "$W/old.before" - > /dev/null || bad "tweaksd changed kia-tweaks/"
    snapshot "$M/data/nemesis/backup/kia-tweaks.systemui" | diff "$W/backup.before" - > /dev/null \
        || bad "tweaksd changed backup/kia-tweaks.systemui"
    RUNS=$((RUNS + 1))
}
RUNS=0
want() { cat "$DATA/want/$1" 2>/dev/null; }
no_actions() { if [ -s "$ACT" ]; then bad "$1: scripts ran: $(tr '\n' ';' < "$ACT")"; else ok "$1: no tweak script ran"; fi; }
logged() { grep -q -- "$1" "$W/tweaksd.log" && ok "logged: $1" || bad "not logged: $1"; }
in_state() { grep -q -- "$1" "$DATA/state.json" && ok "state.json has $1" || bad "state.json lacks $1"; }
not_in_state() { grep -q -- "$1" "$DATA/state.json" && bad "state.json has $1" || ok "state.json lacks $1"; }

# ---- the car as kia.tweaks 1.3 left it, with cabinwright.tweaks installed beside it
rm -rf "$M"; mkdir -p "$A" "$M/proc/4242"
package cabinwright.tweaks 1.4
cp -R "$HERE/package/svc" "$A/cabinwright.tweaks/"
package kia.tweaks 1.3
mkdir -p "$A/kia.tweaks/svc"; cp "$HERE/package/svc/tweaksd.sh" "$A/kia.tweaks/svc/"
for p in cabinwright.tweaks kia.tweaks; do
    tweak "$A/$p" auto-dst service 'default=on
'
    tweak "$A/$p" skip-consent oneshot 'risk=system
'
    tweak "$A/$p" eth0-guard service 'retired=1
'
done
package tweaks.adb 1.0
tweak "$A/tweaks.adb" adb-wifi oneshot 'risk=system
'
car skip-consent on; car adb-wifi on
# kia.tweaks' tweaksd, running (its command line), and its data
printf 'sh\0/data/nemesis/apps/kia.tweaks/svc/tweaksd.sh\0' > "$M/proc/4242/cmdline"
mkdir -p "$OLD/want" "$OLD/logs" "$OLD/last" "$OLD/shadow" "$OLD/run" "$OLD/index"
echo 1 > "$OLD/want/auto-dst"; echo 1 > "$OLD/want/skip-consent"; echo 1 > "$OLD/want/adb-wifi"
echo 0 > "$OLD/want/eth0-guard"
echo 1761431000 > "$OLD/gen"
echo '{"time":1761431000,"pid":4242,"tweaks":{"skip-consent":{"want":"on","state":"on"}}}' > "$OLD/state.json"
echo "earlier log line" > "$OLD/logs/skip-consent.log"
echo "1761400000 restarted" > "$OLD/last/eth0-guard"
echo boot-1 > "$OLD/skip-consent.pending"
echo 4242 > "$OLD/run/auto-dst.pid"   # kia.tweaks' own bookkeeping: never imported
cp -R "$A/tweaks.adb" "$OLD/shadow/tweaks.adb"
mkdir -p "$M/data/nemesis/backup/kia-tweaks.systemui"
echo stock-apk > "$M/data/nemesis/backup/kia-tweaks.systemui/SystemUI.apk"
echo stock-odex > "$M/data/nemesis/backup/kia-tweaks.systemui/SystemUI.odex"
: > "$ACT"

echo "A. kia.tweaks' tweaksd is running: stand by, import"
tweaksd 3
no_actions "standing by"
logged "standing by until it stops"
logged "imported kia.tweaks' data"
check '[ "$(want auto-dst)$(want skip-consent)$(want adb-wifi)$(want eth0-guard)" = 1110 ]' "switches imported"
check '[ "$(cat "$DATA/gen")" = 1761431000 ]' "generation imported"
check '[ -z "$(ls "$DATA/index")" ] && [ -z "$(ls "$DATA/run")" ]' "nothing indexed or run while standing by"
in_state '"standby":"kia.tweaks"'
in_state '"skip-consent":{"want":"on","state":"on"}'
check 'grep -q "earlier log line" "$DATA/logs/skip-consent.log"' "logs imported"
check '[ -f "$DATA/last/eth0-guard" ] && [ "$(cat "$DATA/skip-consent.pending")" = boot-1 ]' "last/ and the pending mark imported"
check '[ -f "$DATA/shadow/tweaks.adb/NEMESIS.data" ]' "pack copies imported"
check '[ "$(cat "$M/data/nemesis/backup/cabinwright.tweaks.systemui/SystemUI.odex")" = stock-odex ]' "skip-consent backup copied"
check '[ ! -e "$DATA/run/auto-dst.pid" ]' "kia.tweaks' run/ not imported"
check '[ "$(cat "$DATA/imported")" != final ]' "import not final while standing by"
# the old app changes a switch meanwhile: followed while standing by
echo 0 > "$OLD/want/adb-wifi"
echo '{"time":1761431100,"pid":4242,"tweaks":{"adb-wifi":{"want":"off","state":"on"}}}' > "$OLD/state.json"
tweaksd 1
check '[ "$(want adb-wifi)" = 0 ]' "follows kia.tweaks' switches while standing by"
echo 1 > "$OLD/want/adb-wifi"
echo '{"time":1761431200,"pid":4242,"tweaks":{"adb-wifi":{"want":"on","state":"on","note":"back"}}}' > "$OLD/state.json"
tweaksd 1
no_actions "still standing by"

echo "B. kia.tweaks' tweaksd stops: take over"
rm -rf "$M/proc/4242"
tweaksd 3
logged "import from kia.tweaks done"
check '[ "$(cat "$DATA/imported")" = final ]' "import final"
check '! grep -q disable "$ACT"' "nothing turned off"
check '[ "$(cat "$M/car/skip-consent")$(cat "$M/car/adb-wifi")" = onon ]' "skip-consent and adb-wifi still on"
not_in_state '"standby"'
in_state '"auto-dst":{"want":"on"'
in_state '"skip-consent":{"want":"on","state":"on"'
check '[ -d "$DATA/shadow/kia.tweaks" ]' "kia.tweaks (still installed) is kept as a pack copy"
# kia.tweaks' files change later: never imported again
echo 0 > "$OLD/want/skip-consent"; echo '{"time":1,"tweaks":{}}' > "$OLD/state.json"
tweaksd 2
check '[ "$(want skip-consent)" = 1 ]' "no second import"
check '! grep -q disable "$ACT"' "still nothing turned off"

echo "C. kia.tweaks removed: its tweaks continue from cabinwright.tweaks"
rm -rf "$A/kia.tweaks"
KT_TEST_DEPART_AFTER=0 tweaksd 3
check '! grep -q disable "$ACT"' "nothing turned off"
check '[ "$(cat "$M/car/skip-consent")" = on ]' "skip-consent still on"
not_in_state '"departed"'
in_state '"skip-consent":{"want":"on","state":"on"'
in_state '"auto-dst":{"want":"on"'
logged "skip-consent: kia.tweaks was removed; skip-consent continues from cabinwright.tweaks"
check '[ ! -e "$DATA/shadow/kia.tweaks" ]' "kia.tweaks' copy dropped"
check '[ "$(cat "$DATA/index/skip-consent")" = "$A/cabinwright.tweaks/tweaks/skip-consent" ]' "skip-consent runs from cabinwright.tweaks"

echo "D. a removed pack's tweak that another pack provides continues from it"
package a.pack 1.0; tweak "$A/a.pack" shared-x oneshot
package b.pack 1.0; tweak "$A/b.pack" shared-x oneshot
car shared-x on; echo 1 > "$DATA/want/shared-x"
tweaksd 2
check '[ "$(cat "$DATA/index/shared-x")" = "$A/a.pack/tweaks/shared-x" ] && [ -d "$DATA/shadow/a.pack" ]' "shared-x from a.pack, copy kept"
rm -rf "$A/a.pack"
KT_TEST_DEPART_AFTER=0 tweaksd 3
check '! grep -q "disable .* shared-x" "$ACT"' "shared-x not turned off"
check '[ "$(cat "$DATA/index/shared-x")" = "$A/b.pack/tweaks/shared-x" ]' "shared-x continues from b.pack"
not_in_state '"departed"'
check '[ ! -e "$DATA/shadow/a.pack" ]' "a.pack's copy dropped"

echo "E. control: a removed pack's own tweak is turned off from its copy"
package c.pack 1.0; tweak "$A/c.pack" only-c oneshot
car only-c on; echo 1 > "$DATA/want/only-c"
tweaksd 2
rm -rf "$A/c.pack"
KT_TEST_DEPART_AFTER=0 tweaksd 4
check 'grep -q "disable c.pack only-c" "$ACT"' "only-c turned off with the copy's disable.sh"
check '[ "$(cat "$M/car/only-c")" = off ]' "only-c off"
check '[ ! -e "$DATA/shadow/c.pack" ] && [ ! -e "$DATA/index/only-c" ]' "c.pack's copy and tweak gone"
check '[ "$(cat "$M/car/skip-consent")$(cat "$M/car/adb-wifi")$(cat "$M/car/shared-x")" = ononon ]' "the others still on"

echo "kia.tweaks' files were only read"
ok "kia-tweaks/ and backup/kia-tweaks.systemui unchanged by all $RUNS runs (checked after each)"

if [ $FAILS = 0 ]; then echo "all passed ($SH)"; else
    echo "--- tweaksd log"; cat "$W/tweaksd.log"; echo "$FAILS failed ($SH)"; exit 1; fi
