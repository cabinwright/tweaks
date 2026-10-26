# kia-tweaks

Status: design, 2026-10-25. NEMESIS package `kia.tweaks`, published through the kia-apps store.

One package of small, switchable head-unit tweaks, each with a plain description, a state, and
an on/off switch in a **Tweaks** app (All Menus, kia-menu's `KiaPage` look). A tweak is a folder
of shell scripts; adding one is adding a folder. Other NEMESIS packages can bring tweaks of their
own (tweak packs, below), shown and switched in the same app.

## Layout

```
app/                       Tweaks app, package dev.kiatweaks (kia-menu build-app.sh --ui)
package/NEMESIS.data       id=kia.tweaks; app.0 = the app; service.0 = tweaksd (uid root)
package/svc/tweaksd.sh     the root service
package/tweaks/<id>/
    tweak.conf             name=, summary=, description=, firmware= (exact strings, or *),
                           kind=service|oneshot, default=off|on, risk=normal|system,
                           retired=1, replaces=<ids>, conflicts=<ids> (see Lifecycle)
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
   Every round turns tweaks off before it turns any on (see `replaces=` / `conflicts=`).
4. write `/data/nemesis/kia-tweaks/state.json` *and* `/sdcard/kia-tweaks/state.json` (the app
   can read the latter): per tweak `{state, text, last_change, last_error, log tail}`

`risk=system` tweaks need a confirmation step in the app (what it changes, how to undo, that
the head unit reboots if needed) before the switch turns on.

## Tweak packs

A tweak pack is any NEMESIS package with a `tweaks/` folder: `/data/nemesis/apps/<package>/tweaks/<id>/`,
each folder exactly like one of kia.tweaks' own (`tweak.conf`, `status.sh`, `run.sh` or
`enable.sh` / `disable.sh`). Its `NEMESIS.data` needs only `[nemesis]` with `id=`, `version=`,
`name=` (e.g. `types=application` with nothing else). Packs let tweaks ship under their own
license and on their own schedule (tweaks ported from GPL/AGPL sources live in packs, not here).

- tweaksd keeps `$INDEX` (`/data/nemesis/kia-tweaks/index/<id>`: the tweak's folder). Sources, in
  order: kia.tweaks' own `tweaks/`, then each pack by package id. An id belongs to the first
  package that has it; a clash is logged and the later one skipped. The app lists tweaks the
  same way.
- **A pack has no install hooks.** NEMESIS runs a package's `preuninstall` / `postuninstall` on
  every *update* too (an update is uninstall + install), and the hooks can't tell the two apart.
  A hook that undid a tweak on uninstall would undo it on every update, and a hook-less removal
  must not leave changes behind either, so lifecycle belongs to tweaksd, which can tell them
  apart by waiting (below).

## Lifecycle: nothing is stranded

A package can go away while its tweaks are on, and an update can drop or rename a tweak. None of
that may leave a change on the car that nothing can turn off any more.

- **Shadow copies.** tweaksd copies every installed pack to
  `/data/nemesis/kia-tweaks/shadow/<package>/`, and refreshes the copy when the pack's `version=`
  changes (not while a NEMESIS install is running, so a half-written pack isn't copied).
- **pending.** When a pack's folder disappears, its tweaks are left exactly as they are and
  reported `"pending": true` while tweaksd waits to see whether it comes back: an update removes
  the package for a moment. The wait restarts while any `nemesis install` / `uninstall` runs.
- **departed.** After 60 s gone with no install running, the pack was removed: its tweaks are
  indexed from the shadow copy, reported `"departed": true`, and turned off with the copy's own
  scripts whatever the switch says. Once they are all off, the copy and their state go.
  A pack that comes back during the wait just carries on (copy kept, nothing turned off).
- **orphan.** A oneshot tweak that is on (or in error) whose files are gone with no copy (e.g.
  removed before tweaksd ever saw it) can't be turned off from here. It stays in `state.json` as
  `"orphan": true`, state `error`, instead of being forgotten; reinstalling its pack picks it up
  again. The app shows departed, pending and orphan tweaks as read-only "left behind" rows.
- **retired=1.** The package no longer offers the tweak: tweaksd turns it off whatever the
  switch says, and the app hides it once it is off. **A tweak that changes the system
  (kind=oneshot or risk=system) is never removed from its package, only retired**: the folder
  stays for good, with working `disable.sh` and `status.sh`, so an install that still has it on
  can turn it off. Only kind=service tweaks, which change nothing that outlives their `run.sh`,
  may simply be dropped (tweaksd stops a run.sh whose folder is gone). An id is never reused
  with a different kind. `tools/check-tweak-ids.sh` enforces both against every earlier `v*`
  tag, in CI and locally.
- **replaces=<ids>** renames a tweak: the app carries the old ids' switch over to the new one,
  and the new one waits until the old ones are off. **conflicts=<ids>**: the tweak waits until
  those are off, and while it is on they wait for it ("waiting for X to turn off"). Each round
  handles every tweak that should be off before any that should be on, so a replacement or a
  conflicting tweak never runs alongside the other. The usual rename: the old folder stays with
  `retired=1`, the new one says `replaces=<old id>`.
- **Updates of a pack's service tweaks.** A run.sh keeps running the old script after its pack
  is updated, so tweaksd restarts it when the pack's version changes.

## Updating tweaksd itself

NEMESIS restarts the service on an update, but sometimes a moment before the update has
replaced its files, so the old script would keep running. tweaksd checks its own file every round
(`ls -l` of `$0`) and, when it has changed, stops its run.sh children and `exec`s the new script.
It also stops every run.sh at start, since one left over from before an update runs old code.

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
