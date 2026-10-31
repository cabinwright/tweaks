# Writing a tweak

A tweak is a folder of shell scripts with a `tweak.conf`. The store's tweak runner
(`cabinwrightd`) runs it and the Tweaks app shows it with an on/off switch. The runner, its
journal, safe mode and the broker are described in the store's
[design](https://github.com/cabinwright/store/blob/main/docs/design.md) ("Tweaks"), which is the
contract; this page is the practical side.

## Where tweaks live

```
tweaks/<id>/
    tweak.conf             what it is and what it needs
    run.sh                 kind=service: runs while the switch is on
    enable.sh              kind=oneshot: apply (exit 0 = done; must be safe to run again)
    disable.sh             undo what the journal can't (see below)
    status.sh              optional: prints one line, "on|off|error <short text>"
lib/                       shared files (this package: tweakpatch.jar)
```

The folder goes in this package (`package/tweaks/<id>/`) or in a tweak pack: any `tweaks`-tier
package in the store index, which holds only `tweaks/` and `lib/`. The store writes every
package's NEMESIS manifest at install. A tweak id is lower case letters, digits and `-`, and belongs to one
package.

## tweak.conf

```
name=Automatic daylight saving time
summary=Changes the clock for daylight saving time
description=Moves the clock forward in March and back in November.
firmware=CVEV.USA.0000.V015.012.260507
kind=service
default=on
need=binder:com.hkmc.micom.time 3,4 | Read and set daylight saving time through the head unit's clock service
need=setting:system/summer_time | Keep the "Daylight saving time" switch in the clock settings in step
```

- `firmware=`: exact `ro.build.product` strings, comma-separated, or `*`. On other firmware
  the tweak is listed but can't be turned on.
- `kind=service | oneshot`, `default=off | on`, optional `conflicts=<ids>` (the tweak waits
  until those are off).
- One `need=` line for every privileged thing the scripts do: `<need> | <reason>`. The reason
  is what the driver reads before agreeing, so write it in plain words about the car, not
  about Android. The store shows "Changes system files" for a tweak with any `file:` need and
  "Changes system settings" otherwise.

| Need | Allows | Command |
|---|---|---|
| `file:<path>@<md5>[,<md5>…]` | replacing that file while it is one of those (stock) versions | `kt file replace <path> <new>` |
| `prop:<name>` | setting that property | `kt prop set <name> <value>` |
| `setting:<table>/<name>` | changing that Android setting | `kt setting put <table> <name> <value>` |
| `service:<name>` | starting or stopping that init service | `kt service start\|stop <name>` |
| `kill:<process>` | restarting that process | `kt kill <process>` |
| `dump:<service>` | reading that binder service's state | `kt dump <service>` (`dumpsys`) |
| `binder:<service> <codes>` | those binder transaction codes | `kt binder <service> <code> <args…>` (`service call` syntax) |
| `root` | anything (first-party review only) | `kt root <command>` |

Reads need nothing: `kt prop get`, `kt setting get`, `kt file md5 <path>`, `kt ps`.

Unknown keys fail CI.

## What a script can do

Scripts run as the tweak's own uid, in its folder, with `$TWEAK_ID`, `$TWEAK_DIR`,
`$TWEAK_DATA` (a private directory, kept across restarts) and `kt` on `$PATH`. That uid can run
`sh`, toolbox, `getprop` and `app_process`, read its folder and `lib/`, and write `$TWEAK_DATA`.
Everything else goes through `kt`: settings, `am`, `service call`, `kill`, logcat, files outside
`$TWEAK_DATA`. A `kt` call the tweak didn't declare fails with exit 70 and puts the tweak in
`error`.

So: do the work unprivileged in `$TWEAK_DATA`, and keep the `kt` steps few and final.
Anything a script prints goes to the tweak's log, which the Tweaks app shows; start lines with
`$(date)` for the app to show their time.

The head unit is Android 4.4: mksh and toolbox only (no `sed`, `awk`, `head`, `tail`, `tr`,
`printf`, `pidof` or `which`). mksh runs every part of a pipeline in a subshell, so
`cmd | read var` sets nothing; use `$( )` and parameter expansion. Lint checks the scripts as
ksh, the nearest dialect.

## Turning off

The runner records every `kt` change before it happens: the original file (in its own backup),
the previous property or setting value. Turning a tweak off, removing its pack, or safe mode
replays that record backwards, so most tweaks need no undo code at all.

`binder`, `kill`, `service` and `root` steps leave nothing to restore, so a tweak that uses
them for a lasting change must ship `disable.sh` (CI checks), oneshot or service. Turning off
runs, in order: the service's `run.sh` is stopped, `disable.sh` runs, then the record is
replayed. If off should deliberately leave a change in place, `disable.sh` says why in a
comment, and for a recorded value calls `kt keep <need>` so the replay leaves it too (as
`auto-dst`'s does: turning it off leaves the clock and its settings checkbox as they are).

`status.sh` should describe the car, not the script: check the actual files or values. Without
one the runner reports from its record.

## Example: replacing a system file

`skip-consent` rebuilds SystemUI from the car's own stock files, so nothing of the head unit's
is shipped:

1. `tweak.conf` declares `file:/system/priv-app/SystemUI.apk@<stock md5>` and the same for
   `SystemUI.odex`.
2. `enable.sh` runs `tweakpatch` (`lib/tweakpatch.jar`, under `app_process` with
   `ANDROID_DATA` in `$TWEAK_DATA`) to rebuild the patched `classes.dex` from the stock odex and
   a delta (`systemui.lpd`), adds it to a copy of the stock apk, and runs `dexopt --preopt` on
   the result, all in `$TWEAK_DATA`, checking the result's md5.
3. Then `kt file replace` for each file. The runner keeps the stock files; turning the tweak
   off puts them back byte for byte. `disable.sh` only notes that a restart is needed.

`systemui/build.sh` builds the delta and prints the checksums `enable.sh` checks against;
`systemui/restore-systemui.sh` is a USB rescue that restores the runner's backup by hand.

## Trying it

On the Mac, a fake `kt` early on `$PATH` that logs its arguments is enough to run most scripts:

```sh
mkdir -p /tmp/kt && printf '#!/bin/sh\necho "kt $*" >&2\n' > /tmp/kt/kt && chmod +x /tmp/kt/kt
PATH=/tmp/kt:$PATH TWEAK_DATA=/tmp/kt/data sh package/tweaks/auto-dst/run.sh check
```

On the car, install the package from the store and switch the tweak in the Tweaks app; its log
is on the tweak's page.
