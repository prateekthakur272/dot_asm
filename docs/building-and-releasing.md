# Building and releasing

## Requirements

- **Flutter** (stable channel). CI uses 3.50.0; the app needs a Dart SDK matching `sdk: ^3.14.0` in `pubspec.yaml`.
- The Flutter desktop toolchain for the system you build on: Xcode on macOS, Visual Studio with the "Desktop development
  with C++" workload on Windows, and on Linux:

  ```bash
  sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  ```

- To build an installer you must be on the target operating system: a DMG needs macOS, an installer `.exe` needs Windows,
  a `.deb` needs Linux.

## Everyday commands

```bash
flutter pub get                 # install dependencies
flutter run -d macos            # run the app (or -d windows, -d linux)
flutter analyze                 # static analysis
flutter test                    # run all tests
dart format lib test            # format the code
flutter test tool/screenshots.dart   # re-render the screenshots (macOS)
```

If you add or change a file in `assets/` while the app is running, stop it and run it again: a hot restart does not
reload the asset list.

## Where the app's identity comes from

| What | Where |
|---|---|
| **Version** and build number | `version:` in `pubspec.yaml` (for example `1.0.0+1`). It is written only there; the build passes it to the app and `AppMetadata` reads it back at runtime |
| Name, vendor, tagline, links | `AppConfig` in `lib/utils/app_config.dart` |
| Application id | `io.github.prateekthakur272.dotasm` (macOS `PRODUCT_BUNDLE_IDENTIFIER` in `macos/Runner/Configs/AppInfo.xcconfig`, Linux `APPLICATION_ID` in `linux/CMakeLists.txt`) |
| Executable name | `BINARY_NAME` in `windows/CMakeLists.txt` and `linux/CMakeLists.txt` |
| Marketplace listing | `.marketplace/` (see below) |

## Installers

Installers are made with [Fastforge](https://fastforge.dev). Each format has a `make_config.yaml` under its platform's
`packaging/` folder:

| Platform | Command | Needs |
|---|---|---|
| macOS | `fastforge package --platform macos --targets dmg,pkg` | `npm install -g appdmg` |
| Windows | `fastforge package --platform windows --targets exe,msix` | [Inno Setup](https://jrsoftware.org/isinfo.php) |
| Linux | `fastforge package --platform linux --targets deb,rpm,appimage` | `rpm`, `patchelf`, `locate` and [`appimagetool`](https://github.com/AppImage/appimagetool) |

```bash
dart pub global activate fastforge
```

Fastforge builds the release app itself, then packages it. The files are written to `dist/<version>/` (git-ignored). The
macOS app is a universal binary (Apple silicon and Intel), so one DMG and one PKG cover both.

| Format | Config | What it is |
|---|---|---|
| `dmg` | `macos/packaging/dmg/make_config.yaml` | Drag-to-Applications disk image |
| `pkg` | `macos/packaging/pkg/make_config.yaml` | macOS installer package |
| `exe` | `windows/packaging/exe/make_config.yaml` | Windows setup program (Inno Setup) |
| `msix` | `windows/packaging/msix/make_config.yaml` | MSIX package (unsigned) |
| `deb` | `linux/packaging/deb/make_config.yaml` | Debian / Ubuntu package |
| `rpm` | `linux/packaging/rpm/make_config.yaml` | Fedora / RHEL / openSUSE package |
| `appimage` | `linux/packaging/appimage/make_config.yaml` | Single-file app for any x86-64 distribution |

## Releasing a new version

Releases are built by GitHub Actions (`.github/workflows/release.yml`) when you push a version tag.

1. Set the new version in `pubspec.yaml` (for example `version: 1.0.1+1`), commit and merge it.
2. Tag the commit with the same version and push the tag:

   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```

3. The workflow then:
   1. **verifies** that the tag matches the `pubspec.yaml` version (a suffix like `v1.0.1-beta.1` is allowed and marks a
      pre-release), then runs `flutter analyze` and `flutter test`;
   2. builds the **macOS**, **Windows** and **Linux** installers in parallel with Fastforge;
   3. writes `SHA256SUMS.txt` and publishes a **GitHub Release** with every installer and generated release notes. It
      only publishes if all three builds succeed.

You can also run the **Release** workflow by hand from the GitHub Actions tab: it builds everything and keeps the
installers as downloadable workflow artifacts without publishing.

CI (`.github/workflows/ci.yml`) runs `flutter analyze` and `flutter test` on every push to `main` and every pull request.

The app checks `releases/latest` of the repository on start and tells the user about a newer version, so a published
release is also how an update reaches existing users.

## The marketplace listing

The `.marketplace/` folder at the root of the repository is what the marketplace reads from the **default branch**:

```
.marketplace/
  app-info.yaml        name, tagline, description, category, platforms, developer, links, tags
  app-icon.png         the app icon
  screenshots/*.png    the images shown on the listing (1440x900 at 1.5x)
```

- **Edit the text** in `app-info.yaml`. Keep `tagline` to one line and the description to a few short paragraphs; it should
  match `AppConfig.TAGLINE` and `AppConfig.DESCRIPTION`.
- **Refresh the icon** by copying `assets/icons/app_icon.png` over `.marketplace/app-icon.png` when the icon changes.
- **Refresh the screenshots** with `flutter test tool/screenshots.dart` (macOS). The same images are written to
  `docs/screenshots/`, which the README and the docs use, so both stay in step. Add or remove a screenshot by editing the
  list at the bottom of that script.
- **Checklist before a release:** the version in `pubspec.yaml`, the description in `app-info.yaml`, the screenshots, and
  the README features table all describe the same app.

### Listing copy at a glance

| Field | Value |
|---|---|
| Name | dot ASM |
| Tagline | Learn assembly and design processors: run code on a simulated CPU and watch it work. |
| Category | Education |
| Platforms | macOS (Apple silicon and Intel), Windows, Linux |
| Developer | Prateek Thakur |
| Privacy | Fully offline. No account, no analytics, no network use except the optional update check against GitHub releases. |
| Price | Free and open source |
| Keywords | assembly, processor, CPU, simulator, emulator, education, RISC-V, ARM, x86, computer architecture |
