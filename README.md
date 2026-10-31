# Cabinwright tweaks

Small, switchable tweaks for Kia/Hyundai head units running [NEMESIS](https://github.com/xwtk/hmg_nemesis),
each with an on/off switch in the **Tweaks** app. Written for the 2023 Kia EV6 (Gen5W, firmware
`CVEV.USA.0000.V015.012.260507`). NEMESIS package `cabinwright.tweaks`, installed from the
[Cabinwright store](https://github.com/cabinwright/store).

| Tweak | What it does |
|---|---|
| Automatic daylight saving | Flips the head unit's own daylight-saving switch on the US/Canada schedule. |
| Skip start-up screen | No consent / driver screen at start-up. Changes SystemUI on `/system`, so it asks first and needs a restart. |

More tweaks come as tweak packs from the store, such as
[tweaks-projection](https://github.com/cabinwright/tweaks-projection); they show up in the same app.

## How it works

The store's `cabinwrightd` runs every tweak: it keeps the switches, runs the scripts as an
unprivileged uid per tweak, does their privileged steps through `kt` within what each tweak
declared, and records every change so that turning a tweak off puts the original back. The
store's [design](https://github.com/cabinwright/store/blob/main/docs/design.md) has the details.

| Part | What it is |
|---|---|
| `app/` | The Tweaks app (`app.cabinwright.tweaks`): lists the tweaks, their state, needs and log, and switches them, through the store's broker (`CarBroker`, capability `tweaks`). |
| `package/tweaks/<id>/` | One folder per tweak: `tweak.conf` plus shell scripts. [docs/writing-a-tweak.md](docs/writing-a-tweak.md) has the format. |
| `patch/` | `tweakpatch`, a small tool run on the car that rebuilds patched system code from the car's own stock files. |
| `systemui/` | Builds the skip-consent delta (`patch.py`, `build.sh`) and the USB rescue script. |
| `tests/tweakpatch-test.sh` | Host test: `tweakpatch`, as R8 shrinks it, against generated deltas and zips. |
| `docs/` | Writing a tweak, and notes on the head unit's internals. |

**No manufacturer code is shipped.** The skip-consent tweak carries a delta. On the car, `tweakpatch`
rebuilds the patched SystemUI from the unit's own stock files, and only if every checksum
matches. The store keeps the stock files and puts them back exactly when the tweak is turned
off. If the head unit ever can't reach the Tweaks app, `systemui/restore-systemui.sh` on a
NEMESIS USB stick puts stock SystemUI back from the store's backup.

## Build

```sh
CABINWRIGHT_MENU=../menu sh build.sh     # -> dist/cabinwright.tweaks.zip, and R8's name maps
CABINWRIGHT_MENU=../menu sh tests/tweakpatch-test.sh
sh ../menu/api/tools/lint.sh .           # ktlint, detekt, ShellCheck
```

`CABINWRIGHT_MENU` is a checkout of the Cabinwright menu repo (CI pins its release `v1.0`):
its `api/` (`CarPage`, `CarBroker`) is compiled into the app, and its `api/tools` build and
lint everything here with pinned tools (Kotlin, R8, Android 4.4's `android.jar`, ktlint,
detekt, ShellCheck). Needs the Android SDK's build-tools 29.0.2, JDK 11 and Python 3.
Rebuilding the delta also needs the car's stock SystemUI and `bsdiff4==1.3.1` (see
`systemui/build.sh`).

The app and `tweakpatch` are Kotlin, compiled against API 19 and shrunk by R8;
`dist/cabinwright.tweaks.map` and `dist/cabinwright.tweaks-tweakpatch.map` are their name
maps, for reading stack traces (retrace). The code the skip-consent tweak puts into SystemUI
is smali (`systemui/patch.py`), shipped only as a delta.

## License

MIT (see `LICENSE`), Copyright (c) 2026 hazptr. Tweaks ported from HMG Leafia Plus and
other community packages ship separately as tweak packs, under their own licenses.
