// ignore_for_file: constant_identifier_names

/// Static application configuration: the name, credits and links shown in the About and developer dialogs.
///
/// Compile-time constants only. What the running app reports about itself (version, build number, bundle id) is
/// read at runtime by `AppMetadata` in utils/app_metadata.dart.
final class AppConfig {
  const AppConfig._();

  static const String NAME = 'dot ASM';

  /// Lower-case, space-free identifier for folders and files (`~/.dotasm`, `dotasm.log`, autostart entry).
  static const String SLUG = 'dotasm';
  static const String COPYRIGHT =
      'Copyright © 2026 dev.prateekthakur. All rights reserved.';
  static const String VENDOR = 'Prateek Thakur';
  static const String TAGLINE = 'A fast, file-first desktop app.';
  static const String DESCRIPTION =
      'dot ASM is a fast, file-first desktop app.';
  static const String REPOSITORY =
      'https://github.com/prateekthakur272/dot_asm';
  static const String HOMEPAGE = REPOSITORY;
  static const String DEVELOPER_URL = 'https://github.com/prateekthakur272';
  static const String MORE_APPS_URL =
      'https://prateekthakur272.github.io/github-marketplace/';
  static const String ISSUES_URL = '$HOMEPAGE/issues/new';

  /// GitHub Releases page — opened when the user clicks "Download" in the update dialog.
  static const String RELEASES_URL = '$HOMEPAGE/releases/latest';

  /// GitHub REST API endpoint for the latest release — used by UpdateChecker.
  static const String RELEASES_API_URL =
      'https://api.github.com/repos/prateekthakur272/dot_asm/releases/latest';
}
