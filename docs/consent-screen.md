# Boot consent screen (SystemUI)

The "Confirm" / driver-select screen shown at start-up is SystemUI's consent screen,
`com.android.systemui.consentscreen` in `/system/priv-app/SystemUI.apk` (deodex with
`baksmali x -a 18`). Names below are from firmware `CVEV.USA.0000.V015.012.260507`.

| Name | Role |
|---|---|
| `consentscreen/D` | Controller (a SystemUI service, extends `com.android.systemui.l`). Tags `ConsentScreenUI` / `ConsentScreen`. |
| `D.start()` | Decides at SystemUI start whether to build the screen (below). Registers receiver `G` for `RELOAD_SETTINGS`, `POST_NORMALBOOT`, `com.mobis.user_profile.intent.action.SHOW_CONSENT`, `FORCE_SHOW_CONSENTSCREEN`, `MOBIS_BT_CALL_STATUS`, and `com.hkmc.intent.action.ACTION_ACC_STATUS_CHANGED` when `D.dd()` (user-profile feature on). |
| `D.dc()` | "Agreed": sets `sys.boot.enabled_screen=true`, `sys.boot.confirm_screen=true`, broadcasts `com.hkmc.intent.action.AGREE_USER_LICENSE`. This is what Confirm leads to. |
| `D.db()` | `shouldDisplayWelcomeFirst()`: `E.dY()` and `UserProfileManager.isWelcomeScreenReady()`. |
| `D.isFactoryMode()` | `MiscManager.isFactoryMode()`. |
| `consentscreen/E` | The screen itself (window, driver list, buttons); also sends `AGREE_USER_LICENSE` and `com.mobis.intent.action.HIDE_CONSENT_SCREEN`. |
| `consentscreen/G` | `D`'s broadcast receiver. |

`D.start()` skips the screen when any of these hold, otherwise it builds it:

1. `sys.boot.show_screen` and `sys.boot.confirm_screen` are both true (SystemUI restarted
   after it was already confirmed),
2. `/storage/upgrade/update.cfg` exists (software update in progress),
3. factory mode: calls `dc()` and skips,
4. the welcome screen should show first (`db()`): calls `dc()` and skips.

Cases 3 and 4 show that calling `dc()` without the screen is a path Kia's code already takes.
Other apps (Navi, BT phone, DiPO/CarPlay, rear camera, telematics, `automotive.jar`) listen for
`AGREE_USER_LICENSE` or check `sys.boot.confirm_screen`, so a bypass has to go through `dc()`
(or do exactly what it does) rather than just hiding the window. The screen also comes back on
ACC on (`ACTION_ACC_STATUS_CHANGED` through `G`), not only at boot.
