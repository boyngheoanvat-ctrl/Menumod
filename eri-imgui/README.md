# ERI ImGui rebuild - binary-only menu integration

This is a **new Dear ImGui frontend** built with Metal for iOS ARM64. There is **no need for the original menu source**. It uses Objective-C runtime to call the existing `AVGamesMenu` `segmentTitles` / `rowsForSegment:` factory methods and the `AVG*` row callbacks in the supplied `zsmvn.dylib`. No game features are reproduced or invented.

## Components
- `ERIImGuiOverlay.dylib`: compiled on macOS by the included GitHub Actions workflow.
- `zsmvn_eri_loader.dylib`: original dylib patched to depend on `ERIImGuiOverlay.dylib` by `patch_loader.py`.
- Both are required. The loader alone **will crash on launch** due to the unresolved dependency. This source archive is not a compiled dylib.

## UI
- New dark ImGui menu and horizontally scrolling tabs.
- Animated seven-color, UTF-8 header `Mod By Eri Nguyễn`; other ImGui text cycles through seven colors.
- An `ERI` floating button toggles the menu.
- `AVGToggle`, `AVGCheckbox`, `AVGSlider`, `AVGCombo`, `AVGButton`, `AVGTextField`, and `AVGSection` rows are bridged to their original callbacks (when found).

## Build
Use `.github/workflows/build-ios-imgui-rebuild.yml` in a GitHub repository (it expects code under `eri-imgui/Sources`). The runner builds ARM64 using Apple's iPhoneOS SDK and pins Dear ImGui 1.92.2. This machine has no iPhoneOS SDK, so a real iOS build must be done on macOS.

To package an IPA after a successful build:
1. Place both `zsmvn.dylib` (loader-patched) and `ERIImGuiOverlay.dylib` in `Payload/App.app/Frameworks/` with matching dependency name.
2. (Recommended) include a legitimately licensed font named `ERI-Vietnamese.ttf` at `Payload/App.app/ERI-Vietnamese.ttf` to show Vietnamese diacritics in ImGui.
3. Re-sign all modified app components with a valid iOS certificate / provisioning profile.
4. Test on a device. Backup the original before replacing it.

## Limitations
- Unverified on device, injection/host loading depends on the IPA.
- Row callback signatures for toggle/slider/combo and text were inspected via ARM64 disassembly of the supplied binary. Dynamic runtime behavior may still differ.
- No guarantee all original rows will be available or that gameplay hooks work in the changed app.
- This is **two dylibs**, not a monolithic one-file rebuild.
- The original binary may display UI before the new overlay starts. Runtime bridge tries to dismiss/hide it.