import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';

/// Result of a single update check.
class UpdateResult {
  const UpdateResult({
    required this.version,
    required this.isDismissed,
    this.error,
  });

  /// The newer version string (e.g. `"1.0.1"`), or null when already up to date.
  final String? version;

  /// True when [version] was previously dismissed by the user via "Later".
  final bool isDismissed;

  /// Why the check could not be completed (offline, rate limited ...); null when it ran.
  final String? error;

  bool get failed => error != null;

  bool get hasUpdate => version != null;

  /// True when the update dialog should be shown (update exists and not dismissed).
  bool get shouldShowDialog => hasUpdate && !isDismissed;
}

/// Checks GitHub releases for a newer version of the app.
class UpdateChecker {
  UpdateChecker._();

  static const _webUrl = AppConfig.RELEASES_URL;
  static const _apiUrl = AppConfig.RELEASES_API_URL;

  /// Key in `prefs.json` holding the last version the user dismissed.
  static const _dismissedKey = 'dismissedUpdateVersion';

  /// Finds the latest release and returns an [UpdateResult].
  ///
  /// - [UpdateResult.version] is non-null when a newer release exists.
  /// - [UpdateResult.isDismissed] reflects whether the user already tapped "Later" for that exact version.
  /// - [UpdateResult.error] is set when the latest release could not be found out at all.
  ///
  /// It checks GitHub's `releases/latest` web page first: that redirects to the newest release's tag and is not
  /// restricted by the REST API's 60 req/hr rate limit per IP. The REST API is the fallback.
  static Future<UpdateResult> check(
    String currentVersion, {
    String latestUrl = _webUrl,
    String apiUrl = _apiUrl,
  }) async {
    String? tag;
    var noReleases = false;
    final problems = <String>[];
    try {
      final r = await _latestFromRedirect(latestUrl);
      tag = r.tag;
      noReleases = r.none;
      if (tag == null && !noReleases) problems.add(r.problem!);
    } catch (e, st) {
      Log.warning('update', 'Update check (web) failed', e, st);
      problems.add(_describe(e));
    }
    if (tag == null && !noReleases) {
      try {
        tag = await _latestFromApi(apiUrl);
        problems.clear();
      } catch (e, st) {
        Log.warning('update', 'Update check (API) failed', e, st);
        problems.add(_describe(e));
      }
    }
    if (tag == null) {
      return UpdateResult(
        version: null,
        isDismissed: false,
        error: noReleases || problems.isEmpty ? null : problems.last,
      );
    }

    // Strip a leading "v" so "v1.0.1" compares cleanly to "1.0.0".
    final remote = tag.replaceFirst(RegExp(r'^v'), '');
    if (!_isNewer(remote, currentVersion)) {
      return const UpdateResult(version: null, isDismissed: false);
    }
    return UpdateResult(version: remote, isDismissed: isDismissed(remote));
  }

  static Map<String, String> get _headers => {
    'User-Agent': '${AppConfig.NAME}/${AppMetadata.version}',
  };

  /// `https://github.com/<owner>/<repo>/releases/latest` answers with a redirect to `.../releases/tag/<tag>`.
  static Future<({String? tag, bool none, String? problem})>
  _latestFromRedirect(String url) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers.addAll(_headers);
      final res = await client.send(req).timeout(const Duration(seconds: 10));
      await res.stream.drain<void>();
      if (res.statusCode < 300 || res.statusCode >= 400) {
        return (
          tag: null,
          none: false,
          problem: 'GitHub answered ${res.statusCode}',
        );
      }
      final location = res.headers['location'];
      if (location == null) {
        return (tag: null, none: false, problem: 'GitHub sent no release link');
      }
      final path = Uri.parse(location).pathSegments;
      final at = path.lastIndexOf('tag');
      if (at >= 0 && at + 1 < path.length) {
        return (
          tag: Uri.decodeComponent(path[at + 1]),
          none: false,
          problem: null,
        );
      }
      // Redirected to the releases list: the project has no published release yet.
      return (tag: null, none: true, problem: null);
    } finally {
      client.close();
    }
  }

  static Future<String?> _latestFromApi(String url) async {
    final res = await http
        .get(
          Uri.parse(url),
          headers: {'Accept': 'application/vnd.github+json', ..._headers},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw StateError(
        'GitHub is limiting requests from this network, try again later',
      );
    }
    if (res.statusCode != 200) {
      throw StateError('GitHub answered ${res.statusCode}');
    }
    final tag = (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'];
    if (tag is! String) throw StateError('GitHub sent no release');
    return tag;
  }

  static String _describe(Object e) => switch (e) {
    StateError() => e.message,
    TimeoutException() => 'GitHub did not answer in time',
    SocketException() || http.ClientException() => 'no connection to GitHub',
    _ => 'unexpected answer from GitHub',
  };

  /// Persists [version] as the last dismissed version so the dialog is not
  /// shown again on the next launch for the same release.
  static Future<void> dismissVersion(String version) async {
    AppStore.setFlag(_dismissedKey, version);
  }

  /// Whether the user already chose "Later" for exactly [version].
  static bool isDismissed(String version) =>
      AppStore.flagString(_dismissedKey) == version;

  /// Clears any stored dismissal (used before a manual "Check for Updates…").
  static Future<void> clearDismissed() async {
    AppStore.setFlag(_dismissedKey, null);
  }

  /// Returns true when [remote] is semantically newer than [local].
  static bool _isNewer(String remote, String local) {
    int part(String v, int i) =>
        int.tryParse(v.split('.').elementAtOrNull(i) ?? '0') ?? 0;
    for (var i = 0; i < 3; i++) {
      final r = part(remote, i), l = part(local, i);
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }
}
