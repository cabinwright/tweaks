# R8 rules for tweakpatch (patch/build.sh), on top of the menu's api/tools/app-rules.pro.
# app_process starts it by name: dev.cabinwright.tweaks.patch.Main.main(String[])
-keep class dev.cabinwright.tweaks.patch.Main {
    public static void main(java.lang.String[]);
}
