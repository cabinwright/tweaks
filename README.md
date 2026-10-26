# kia-tweaks

Small, switchable tweaks for Kia head units running [NEMESIS](https://github.com/xwtk/hmg_nemesis),
each with an on/off switch in the **Tweaks** app. Written for the 2023 Kia EV6 (Gen5W, firmware
`CVEV.USA.0000.V015.012.260507`). NEMESIS package `kia.tweaks`.

| Tweak | What it does |
|---|---|
| Automatic daylight saving | Flips Kia's own daylight-saving switch on the US/Canada schedule. |
| Fix wireless Android Auto not connecting | Restarts Kia's Android Auto receiver when it gets stuck after the car's Wi-Fi hotspot was used. |
| Wireless projection with ADB TCP | Stops the Engineering Mode "ADB TCP" switch from breaking wireless Android Auto and CarPlay. |
| Skip start-up screen | No consent / driver screen at start-up. Changes SystemUI on `/system`, so it asks first and needs a restart. |

## How it works

| Part | What it is |
|---|---|
| `app/` | The Tweaks app (`dev.kiatweaks`). It is the only thing that decides which tweaks are on. |
| `package/svc/tweaksd.sh` | Root service: reads the switches from the app (read-only provider), starts and stops tweaks, reports their state. |
| `package/tweaks/<id>/` | One folder per tweak: `tweak.conf` plus shell scripts (`run.sh`, or `enable.sh` / `disable.sh` / `status.sh`). |
| Tweak packs | Other NEMESIS packages with a `tweaks/<id>/` folder of their own. They show up in the same app. |
| `tools/check-tweak-ids.sh` | CI check: a tweak that changes the system is never dropped between releases, only retired. |
| `patch/` | `kiapatch`, a small tool run on the car that rebuilds patched system code from the car's own stock files. |
| `systemui/` | Builds the skip-consent delta (`patch.py`, `build.sh`) and the USB rescue script. |
| `docs/` | Notes on the head unit's internals. |

Tweak packs need no install hooks. tweaksd keeps a copy of each pack, and when a pack is removed
it turns that pack's tweaks off from the copy. A tweak that is no longer offered gets `retired=1`
rather than being deleted. `replaces=` and `conflicts=` order renamed and incompatible tweaks.
[DESIGN.md](DESIGN.md) has the tweak format and the full lifecycle.

**No manufacturer code is shipped.** The skip-consent tweak carries a delta. On the car, `kiapatch`
rebuilds the patched SystemUI from the unit's own stock files, and only if every checksum
matches. The stock files are backed up first and restored exactly when the tweak is turned off.
If the head unit ever can't reach the Tweaks app, `systemui/restore-systemui.sh` on a NEMESIS USB
stick puts stock SystemUI back.

## Build

```sh
KIA_MENU=../kia-menu sh build.sh     # -> dist/kia.tweaks.zip
```

Needs the Android SDK (build-tools 29.0.2, platform 23) and JDK 11. Rebuilding the delta also
needs the car's stock SystemUI and `bsdiff4==1.3.1` (see `systemui/build.sh`).

## License

MIT (see `LICENSE`), Copyright (c) 2026 hazptr. Tweaks ported from HMG Leafia Plus and
other community packages ship separately as tweak packs, under their own licenses.
