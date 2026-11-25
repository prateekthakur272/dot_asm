# dot ASM

A fast, file-first desktop app (Flutter: macOS, Windows, Linux). The core mirrors `devspace`: theme, window shell,
menus, command palette, settings, developer dialog, About, in-app update check and open-at-login.

```
flutter pub get
flutter run -d macos
flutter analyze && flutter test
```

Architecture and rules: [AGENTS.md](AGENTS.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Name, links and repo URL are set in `lib/utils/app_config.dart`.
