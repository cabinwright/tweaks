#!/usr/bin/env python3
"""Skips the start-up consent screen: applied to a deodexed SystemUI smali tree (in place).
See docs/consent-screen.md for the names.

ConsentScreenUI.start() (consentscreen/D) builds the screen at boot unless factory mode is
on or the welcome screen goes first; in both of those cases the head unit's code calls dc() instead,
which records the agreement (sys.boot.enabled_screen / confirm_screen, broadcast
AGREE_USER_LICENSE) without any screen. The hook makes the normal boot path do the same.
The current driver stays as it was. Every other way the screen opens (choosing a driver
from the status bar, a profile with a password, after a software update) is untouched.

usage: patch.py <smali dir>
"""
import sys
from pathlib import Path

D = "Lcom/android/systemui/consentscreen/D;"
FILE = "com/android/systemui/consentscreen/D.smali"
ANCHOR = ("    :cond_14d\n"
          "    invoke-virtual {p0, v4}, %s->T(I)V\n"
          "\n"
          "    goto/16 :goto_7d\n"
          ".end method\n" % D)
# The log line is part of the shipped delta (systemui.lpd) and of the patched SystemUI's
# checksum (SUM_OURS in tweaks/skip-consent/common.sh): build.sh prints both.
HOOK = ("    :cond_14d\n"
        "    invoke-direct {p0}, %s->dc()V\n"
        "    const-string v1, \"ConsentScreenUI\"\n"
        "    const-string v2, \"Cabinwright: consent screen skipped at start-up\"\n"
        "    invoke-static {v1, v2}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I\n"
        "\n"
        "    goto/16 :goto_7d\n"
        ".end method\n" % D)


def main():
    f = Path(sys.argv[1]) / FILE
    text = f.read_text()
    if text.count(ANCHOR) != 1:
        sys.exit("patch.py: ConsentScreenUI.start() isn't the expected code - refusing")
    f.write_text(text.replace(ANCHOR, HOOK))
    print("hooked ConsentScreenUI.start()")


if __name__ == "__main__":
    main()
