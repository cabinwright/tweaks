# kia-tweaks

Status: design, 2026-10-25. NEMESIS package `kia.tweaks`, published through the kia-apps store.

One package of small, switchable head-unit tweaks, each with a plain description, a state, and
an on/off switch in a **Tweaks** app (All Menus, kia-menu's `KiaPage` look). A tweak is a folder
of shell scripts; adding one is adding a folder.

## Layout

```
app/                       Tweaks app, package dev.kiatweaks (kia-menu build-app.sh --ui)
package/NEMESIS.data       id=kia.tweaks; app.0 = the app; service.0 = tweaksd (uid root)
package/svc/tweaksd.sh     the root service
package/tweaks/<id>/
    tweak.conf             name=, summary=, description=, firmware= (exact strings, or *),
                           kind=service|oneshot, default=off|on, risk=normal|system
    run.sh                 kind=service: long-running, started while the tweak is on
    enable.sh, disable.sh  kind=oneshot: apply / undo (must be idempotent; exit 0 = done)
    status.sh              prints one line: "on|off|error <short text>"
package/lib/               shared helpers (e.g. the patch tool dex for SystemUI-type tweaks)
```

The first tweaks:

| id | kind | What |
|---|---|---|
| `auto-dst` | service | Follows daylight saving time automatically (see `tweaks/auto-dst.sh`; Kia's own switch via TimePolicyService). Rule configurable later; US/Canada default. |
| `skip-consent` | oneshot, risk=system, exact firmware | No start-up consent / driver-select screen: rebuilds SystemUI on the car from its own stock files (delta + checksums, nothing of Kia's shipped), backs up, installs; disable restores stock. Built by the owner; scripts and delta land in `tweaks/skip-consent/` later. |

## Who decides what's on

The app is the only writer of the desired state. It keeps it in its own storage (mirrored to
`/sdcard/kia-tweaks/desired.json` purely as a backup, since NEMESIS updates wipe app data) and
exposes it read-only through a ContentProvider, `content://dev.kiatweaks.state/desired`, rows
`(id, on)`. The provider allows reads from uid 0 / 1000 / 2000 and the app itself; nothing
can write through it. tweaksd reads it with the stock `content query` command, so another app
on the car can't flip a tweak (an sdcard request file could be planted by any app; that matters
here because `skip-consent` changes /system).

tweaksd (root, `mode=restart`), every few seconds and on a broadcast from the app
(`dev.kiatweaks.action.APPLY`; tweaksd can't receive broadcasts in sh, so it polls a cheap
"generation" counter column in the same provider instead):

1. read desired state; skip tweaks whose `firmware` doesn't match the car's
2. `kind=service`: start `run.sh` (background, tracked pid) when on, stop it when off
3. `kind=oneshot`: run `enable.sh` / `disable.sh` when desired differs from `status.sh`
4. write `/data/nemesis/kia-tweaks/state.json` *and* `/sdcard/kia-tweaks/state.json` (the app
   can read the latter): per tweak `{state, text, last_change, last_error, log tail}`

`risk=system` tweaks need a confirmation step in the app (what it changes, how to undo, that
the head unit reboots if needed) before the switch turns on.

## The app

Grid or list of tweaks: name, summary, state (with the status text), switch. Tapping opens the
description and recent log. Shows plainly when tweaksd isn't running or a tweak doesn't support
this firmware. Kia look via `KiaPage` (palette, Mobis font, day/night, slim title row).

## Environment notes (Gen5W, Android 4.4)

- No `sed`, `awk`, `head`, `pidof`, `which` on the car: plain `sh` (mksh) parameter expansion,
  `case`, `grep`, `toolbox` commands only. `ps` + `grep` for pids.
- NEMESIS services run as root but with CapEff 0xc0 (no CAP_KILL for other uids' processes):
  `nemesis root 1000 -c '<cmd>'` acts as system.
- `service call`, `settings`, `content`, `am`, `setprop`, `getprop` all work from a root service.
- Package updates reinstall the APK, wiping app data: keep anything that must survive on the sdcard.
