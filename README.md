# Cabinwright tweaks

Small, switchable tweaks for Kia/Hyundai head units running [NEMESIS](https://github.com/xwtk/hmg_nemesis),
each with an on/off switch in the **Tweaks** app. Written for the 2023 Kia EV6 (Gen5W, firmware
`CVEV.USA.0000.V015.012.260507`). NEMESIS package `cabinwright.tweaks`.

| Tweak | What it does |
|---|---|
| Automatic daylight saving | Flips the head unit's own daylight-saving switch on the US/Canada schedule. |
| Skip start-up screen | No consent / driver screen at start-up. Changes SystemUI on `/system`, so it asks first and needs a restart. |

Two older tweaks, "Fix wireless Android Auto not connecting" and "Wireless projection with ADB TCP", are
retired: they are switched off and hidden, and the
[tweaks-projection](https://github.com/cabinwright/tweaks-projection) pack does their job now.

## How it works

| Part | What it is |
|---|---|
| `app/` | The Tweaks app (`dev.cabinwright.tweaks`). It is the only thing that decides which tweaks are on. |
| `package/svc/tweaksd.sh` | Root service: reads the switches from the app (read-only provider), starts and stops tweaks, reports their state. |
| `package/tweaks/<id>/` | One folder per tweak: `tweak.conf` plus shell scripts (`run.sh`, or `enable.sh` / `disable.sh` / `status.sh`). |
| Tweak packs | Other NEMESIS packages with a `tweaks/<id>/` folder of their own. They show up in the same app. |
| `tools/check-tweak-ids.sh` | CI check: a tweak that changes the system is never dropped between releases, only retired. |
| `tests/tweaksd-test.sh` | Host test: tweaksd against a mock head unit (the move from kia.tweaks, removed packs, log rotation). |
| `tests/tweakpatch-test.sh` | Host test: `tweakpatch`, as R8 shrinks it, against generated deltas and zips. |
| `patch/` | `tweakpatch`, a small tool run on the car that rebuilds patched system code from the car's own stock files. |
| `systemui/` | Builds the skip-consent delta (`patch.py`, `build.sh`) and the USB rescue script. |
| `docs/` | Notes on the head unit's internals. |

Tweak packs need no install hooks. tweaksd keeps a copy of each pack, and when a pack is removed
it turns that pack's tweaks off from the copy, unless another installed package provides the same
tweak id: then the tweak continues from that package. A tweak that is no longer offered gets `retired=1`
rather than being deleted. `replaces=` and `conflicts=` order renamed and incompatible tweaks.
[DESIGN.md](DESIGN.md) has the tweak format and the full lifecycle.

**No manufacturer code is shipped.** The skip-consent tweak carries a delta. On the car, `tweakpatch`
rebuilds the patched SystemUI from the unit's own stock files, and only if every checksum
matches. The stock files are backed up first and restored exactly when the tweak is turned off.
If the head unit ever can't reach the Tweaks app, `systemui/restore-systemui.sh` on a NEMESIS USB
stick puts stock SystemUI back.

## Build

```sh
CABINWRIGHT_MENU=../menu sh build.sh     # -> dist/cabinwright.tweaks.zip, and R8's name maps
sh tests/tweaksd-test.sh                 # KT_SH=mksh|bash picks the shell
CABINWRIGHT_MENU=../menu sh tests/tweakpatch-test.sh
sh tools/check-tweak-ids.sh
sh ../menu/api/tools/lint.sh .           # ktlint, detekt, ShellCheck
```

`CABINWRIGHT_MENU` is a checkout of the Cabinwright menu repo (CI pins its release `v1.3`):
its `api/` is compiled into the app, and its `api/tools` build and lint everything here with
pinned tools (Kotlin, R8, Android 4.4's `android.jar`, ktlint, detekt, ShellCheck). Needs the
Android SDK's build-tools 29.0.2, JDK 11 and Python 3. Rebuilding the delta also needs the car's
stock SystemUI and `bsdiff4==1.3.1` (see `systemui/build.sh`).

The app and `tweakpatch` are Kotlin, compiled against API 19 and shrunk by R8;
`dist/cabinwright.tweaks.map` and `dist/cabinwright.tweaks-tweakpatch.map` are their name
maps, for reading stack traces (retrace). There is no Java left: the code the skip-consent
tweak puts into SystemUI is smali (`systemui/patch.py`), shipped only as a delta. On-car
scripts are checked by ShellCheck as ksh, the nearest dialect to the car's mksh; the car
has toolbox only (no sed, awk, head, tail, tr or printf), and mksh runs every part of a pipeline in a
subshell, so `cmd | read var` sets nothing.

## Moving from kia.tweaks

This package used to be `kia.tweaks` (app `dev.kiatweaks`, data in `/data/nemesis/kia-tweaks`).
`cabinwright.tweaks` installs beside it and takes over without turning anything off:

- While kia.tweaks' tweaksd runs, the new tweaksd stands by: it runs no tweak script, and the
  new app says the old package still runs the tweaks.
- With no data of its own, the new tweaksd imports kia.tweaks' (read only): the switches,
  `state.json`, the pack copies, logs, and the skip-consent stock backup
  (`backup/kia-tweaks.systemui` is copied to `backup/cabinwright.tweaks.systemui`). The new app
  takes its switches from that, or from kia.tweaks' own state and `/sdcard/kia-tweaks/desired.json`
  if it starts first.
- Remove kia.tweaks (it has no install hooks). Its tweaksd stops, and the new one takes over
  with the same switches. kia.tweaks' tweaks are all provided by cabinwright.tweaks too, so
  none of them counts as departed.

Tweak packs (`tweaks.projection`, `tweaks.adb`) are found by scanning `/data/nemesis/apps`, so
they carry on unchanged. The store's `docs/migrating-from-kia.md` has the whole switch, with a
script.

## License

MIT (see `LICENSE`), Copyright (c) 2026 hazptr. Tweaks ported from HMG Leafia Plus and
other community packages ship separately as tweak packs, under their own licenses.
