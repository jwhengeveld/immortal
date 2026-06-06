# Changelog

## 1.16 (2026-06-06)

Make Immortal appear as a tile on the Portal TV's stock home (ripleyhome).

- ripleyhome is an Android-TV (Leanback) launcher: it lists apps that declare `CATEGORY_LEANBACK_LAUNCHER` (VLC, the Vewd browser, …), not plain `LAUNCHER` apps — which is why Immortal, Jellyfin, Transistor and Shizuku never showed there. Immortal now declares a Leanback launcher entry, with a 320x180 TV banner, via a launcher-only `activity-alias` (no `HOME` category, so it isn't filtered out as a home app). It opens the normal launcher. Together with the Calls→stock-home bridge, you can hop between Immortal and the stock home in both directions.
- Declared `leanback` and `touchscreen` as optional features so the app installs cleanly on every Portal, touch or TV.

## 1.15 (2026-06-05)

Fix the screensaver's time-per-item control so it works with both touch and the remote.

- In 1.14 the control adjusted only via D-pad left/right, so on touchscreen Portals there was no way to change it. The ◀ / ▶ arrows are now real tap targets, while the remote keeps adjusting with left/right and moving focus away with up/down. The arrows are excluded from D-pad traversal so they don't add extra stops for the remote.

## 1.14 (2026-06-05)

Portal TV polish, from end-to-end testing on the device with its remote.

- **Calls tile** now bridges to the stock Portal TV home (`ripleyhome`) when the touchscreen call UI isn't available, so the remote can still reach calls and the stock app grid.
- **Grid curation:** hide internal/non-user entries (the TV boot flow `rcbootflow` and the stock home), and fold the TV's **Picture Mode** into the Settings folder.
- **Browser:** Chrome ships on every Portal but renders blank and is undriveable by the remote on the TV, so it's hidden there (device `ripley`) in favour of the working Vewd browser. It stays available on the touch models where it works.
- **Screensaver settings on the remote:** focused rows no longer grow outside their card (filled highlight instead of scale), and the time-per-item control is now a left/right stepper you can navigate past — previously the slider trapped focus.

## 1.9 (2026-06-05)

Clearer messaging when app installs are paused on a first-gen Portal.

- Rewrote the paused-install copy across the store banner, the per-app status, the "Install with Immortal" card, the "Install an APK" browser, and the self-updater. The old wording ("reinstall Immortal to restore") was misleading — reinstalling the app doesn't restart the install helper. The new copy is accurate and consistent: installing new apps is paused after a reboot; reconnect to a computer and re-run the installer to add apps; everything else keeps working.
- No functional change — installs, the daemon, and Shizuku support are unchanged from 1.8.

## 1.8 (2026-06-05)

Universal installer — make sideloading work on the Gen-1 Portal+, whose built-in Android installer dialog is broken (renders with no buttons).

- **"Open with Immortal"** (`ApkInstallActivity`): opening any APK — from Chrome, a file manager, or a third-party store like Aurora ("Session/Native" installer mode) — routes through Immortal's silent daemon. Shows an "Install <app>? via Immortal" card; installs with no system dialog.
- **"Install an APK"** browser (`ApkBrowserActivity`): lists APKs in Downloads and installs them on a tap, from the App Store header.
- **Shizuku** (optional): `provision.sh --shizuku` / `-Shizuku` installs Shizuku (if `SHIZUKU_APK_URL` set) and starts its server over ADB, for apps that use the Shizuku API directly. Resolves the version/ABI-specific starter at runtime. Like the daemon, restart after a reboot.
- **Paused banner** copy clarified for Gen-1 ("reinstall Immortal to restore").

## 1.0 (2026-06-05)

Initial public release of Immortal — a custom home-screen layer for discontinued Meta Portal devices.

- **Launcher**: fullscreen app grid, clock/date/weather header, optional Portal Go charge indicator.
- **Folders**: drag one app onto another to create a folder; name, rename, and drag apps back out.
- **Manage mode**: remove apps with a tap; special tiles stay put and non-uninstallable.
- **Calls bridge**: one-tap route to the stock dialer/contacts for WhatsApp and Messenger calling.
- **Screensaver**: photo frame with stock-style widgets, swipe navigation, tap to exit.
- **App Store**: hosted JSON catalog, on-device install via PackageInstaller, live F-Droid resolution.
- **Self-update**: polls a hosted manifest and installs new builds over itself — no cable.
- **Provisioning kit**: one double-click to install, set home + screensaver, and freeze OS updates. Fully reversible.
