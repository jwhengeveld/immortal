# Immortal

A custom home-screen layer for discontinued Meta Portal devices — a play on *Portal*, and on
keeping it alive after Meta wound the platform down. Immortal turns a Portal into a device you
own: your launcher, your screensaver, and an app store that installs a curated catalog
on-device, with remote self-update so it improves over time without a cable.

Package: `com.immortal.launcher` · Target: Meta Portal (Android 10 / API 29, arm64, no GMS).

## What's in it

- **Launcher** (`HomeActivity`) — a fullscreen app grid with a clock/date/weather header and an
  optional charge indicator (shown only on Portal Go, which has a battery). A photo-style
  **Screensaver** button sits top-left; a **Manage** button bottom-right. Manage mode lets you
  remove apps (tap the ✕) and organise the grid into **folders** by dragging one app onto
  another — name them, rename them, and drag apps back out, just like a phone. A green **Calls**
  tile bridges to the stock dialer/contacts for WhatsApp and Messenger calling.
- **Screensaver** (`PhotoDreamService` / `PhotoFrameController`) — a photo frame with stock-style
  clock/battery/date/weather widgets over a rotating photo feed. Swipe to change photos, tap to
  exit. The image source is pluggable (keyless Lorem Picsum by default, Unsplash-ready); weather
  is keyless Open-Meteo + IP geolocation.
- **App Store** (`StoreActivity` / `StoreCatalog`) — renders a hosted JSON catalog
  ([`catalog.json`](catalog.json)) by category and installs apps. F-Droid entries resolve the
  current APK at install time so the catalog never goes stale; your own apps use a direct
  `apkUrl`. **The store is open to community submissions** — built a Portal app?
  [Get it listed](SUBMISSIONS.md).
- **Universal installer** — on the Gen-1 Portal+ (Android 9) the *built-in* Android installer
  dialog is broken (renders with no buttons), so sideloading normally fails. Immortal ships a
  shell-privileged silent-install daemon (started by the kit) that fixes this for the whole
  device: the store and self-update use it, an **"Install with Immortal"** handler
  (`ApkInstallActivity`) catches any APK you open from Chrome or a file manager (set it as the
  default and those installs go silent), and an **"Install an APK"** browser (`ApkBrowserActivity`)
  lists APKs in your Downloads. For Play-Store apps via **Aurora Store**, use Aurora's *Shizuku*
  installer together with Shizuku (`provision.sh --shizuku`) — see
  [Play-Store apps on a first-gen Portal](#play-store-apps-via-aurora-on-a-first-gen-portal) below;
  Aurora's own Session/Native installers can't get past the broken Gen-1 dialog. Newer Portals have
  a working installer and don't need any of this.
- **Self-update** (`UpdateManager`) — Immortal polls [`version.json`](version.json); when it
  advertises a higher `versionCode`, it downloads and installs the new build over itself. No
  cable, no laptop.
- **Provisioning kit** ([`provisioning/`](provisioning/)) — one double-click per device: installs
  Immortal, optionally sets it as the home screen and screensaver, and can freeze OS updates so
  the setup sticks. Fully reversible (`Restore-Portal` / `--restore`).

## Install on a Portal

The easiest path is the [provisioning kit](provisioning/): connect the Portal over USB-C with
ADB enabled, then double-click `Provision-Portal` (macOS/Linux) or `Provision-Portal.bat`
(Windows). It fetches the latest release automatically.

To build from source instead:

```bash
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.immortal.launcher/.HomeActivity
```

## On first-gen Portals (Portal+ Gen-1, Android 9)

Immortal runs on the original Portal+ too — launcher, screensaver, and app store all work. There's
one quirk worth knowing up front, because it's a quirk of that hardware's older software, not a
fault in Immortal:

**The first-gen Portal's built-in Android installer is broken** (it opens a dialog with no
buttons), so apps can't be installed the normal way. Immortal works around this with a small helper
that the provisioning kit starts over USB — after that, the app store, "Install with Immortal," and
sideloading all install silently with no dialog.

That helper can't survive a reboot on this generation (a limitation of running without root on
Android 9 — the same reason tools like Shizuku need re-starting). So **after the Portal restarts,
installing *new* apps is paused until you reconnect it to a computer and run the installer again** —
a 30-second step. Everything else keeps working across reboots: your home screen, screensaver, and
every app you've already installed. Because Portals have no battery and stay plugged in, they
reboot rarely, so in practice you set up your apps once and seldom touch this again. Immortal shows
a clear note in the store when installs are paused, so it's never a mystery.

Newer Portals (Portal Go, Mini, gen-2) have a working installer and don't need any of this.

### Play-Store apps via Aurora on a first-gen Portal

[Aurora Store](https://auroraoss.com) lets you install Play-Store apps (Spotify, etc.) without a
Google account. On the Gen-1 Portal+ its two default installer modes — "Session" and "Native" —
both run into the broken stock installer, and unlike a file you download in Chrome, Aurora keeps
its APK in private storage where Immortal's helper can't reach it. The path that *does* work is
Aurora's **Shizuku** installer, which installs through the same privileged channel Immortal uses:

1. Install **Shizuku** (it's in the Immortal App Store) and **Aurora Store**.
2. Run the provisioning kit's Shizuku step once to start its server: `./provision.sh --shizuku`
   (or `provision.ps1 -Shizuku`). Like Immortal's own helper, it must be re-run after a reboot.
3. In **Aurora → Settings → Installation → Installation method**, choose **Shizuku installer**.
   The first install prompts "Allow Aurora Store to access Shizuku?" — tap **Allow all the time**.

After that, Aurora installs Play-Store apps silently, including split APKs — no dialog, no broken
installer. Verified end-to-end on a Portal+ installing Spotify.

## Releasing

Hosted from this repo:

- [`version.json`](version.json) — the self-update manifest. Bump `versionCode`/`versionName`,
  build a signed release, and attach it as `immortal.apk` to a GitHub Release; devices update on
  their next check.
- [`catalog.json`](catalog.json) — the app-store catalog. Edit and commit; clients pick it up on
  next open (a bundled copy ships as the offline fallback).

Release builds must be signed with the **same** key every time (in-place self-update is
signature-checked). Signing is configured via a git-ignored `keystore.properties`; keep that key
backed up safely — losing it means devices can no longer self-update.

## Disclaimer

Immortal is an independent community project — **not affiliated with, endorsed
by, or sponsored by Meta**. "Meta Portal" and "Portal" are trademarks of Meta
Platforms, Inc., used here only to identify compatible hardware. Provisioning
modifies device settings and is **use-at-your-own-risk** (reversible, but no
guarantees; may void warranty). See [DISCLAIMER.md](DISCLAIMER.md) for the full
text and privacy notes.

## License

MIT — see [LICENSE](LICENSE).
