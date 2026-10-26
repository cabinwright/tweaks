#!/bin/sh
# Checks the package's tweak ids against every earlier release (v* tags), so that nothing a
# release turned on can be stranded by a later one:
# - a kind=oneshot or risk=system tweak never leaves the package: it stays as a retired=1
#   placeholder (with its disable.sh and status.sh) for good. Only kind=service tweaks,
#   which change nothing that outlives their run.sh, may simply be dropped.
# - an id is never reused with a different kind.
# Run from anywhere in the repo:  sh tools/check-tweak-ids.sh [package dir, default package]
# CI needs the full history and tags (actions/checkout with fetch-depth: 0). GIT=<path> picks
# the git to use.
set -e
git() { command "${GIT:-git}" "$@"; }
top=$(git rev-parse --show-toplevel)
cd "$top"
PKG=${1:-package}
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    echo "check-tweak-ids: shallow clone; fetch the full history and tags first" >&2
    exit 2
fi

# key=value from a tweak.conf on stdin, or the default
key() { sed -n "s/^$1=//p" | head -n 1 | grep . || echo "$2"; }

fail=0
err() { echo "check-tweak-ids: $*" >&2; fail=1; }

# the tree as it is now
for conf in "$PKG"/tweaks/*/tweak.conf; do
    [ -f "$conf" ] || continue
    d=${conf%/tweak.conf}; id=${d##*/}
    if [ "$(key retired 0 < "$conf")" = 1 ] && [ "$(key kind service < "$conf")" = oneshot ]; then
        for f in disable.sh status.sh; do
            [ -f "$d/$f" ] || err "$id is retired but has no $f: it must still be able to turn itself off"
        done
    fi
done

tags=$(git tag -l 'v*')
[ -n "$tags" ] || echo "check-tweak-ids: no releases to compare with"
for tag in $tags; do
    for id in $(git ls-tree --name-only "$tag" "$PKG/tweaks/" | sed 's|.*/||'); do
        old=$(git show "$tag:$PKG/tweaks/$id/tweak.conf" 2>/dev/null) || continue
        okind=$(echo "$old" | key kind service)
        orisk=$(echo "$old" | key risk normal)
        conf=$PKG/tweaks/$id/tweak.conf
        if [ ! -f "$conf" ]; then
            if [ "$okind" = oneshot ] || [ "$orisk" = system ]; then
                err "$id ($okind, risk=$orisk in $tag) is gone: keep it, with retired=1, so it can still be turned off"
            fi
            continue
        fi
        kind=$(key kind service < "$conf")
        [ "$kind" = "$okind" ] || err "$id was kind=$okind in $tag and is kind=$kind now: give it a new id"
    done
done
[ $fail = 0 ] && echo "check-tweak-ids: ok ($(echo "$tags" | wc -w | tr -d ' ') releases)"
exit $fail
