import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/utils/update_checker.dart';

void useTempHome() {
  AppStore.homeOverride = Directory.systemTemp
      .createTempSync('dotasm_test_')
      .path;
}

Future<HttpServer> startServer(
  Future<void> Function(HttpRequest req) handler,
) async {
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  srv.listen((r) async {
    try {
      await handler(r);
    } catch (_) {
      try {
        await r.response.close();
      } catch (_) {}
    }
  });
  return srv;
}

Future<void> respond(
  HttpRequest r,
  String body, {
  String contentType = 'application/json',
  int status = 200,
}) async {
  final b = utf8.encode(body);
  r.response.statusCode = status;
  r.response.headers.set('Content-Type', contentType);
  r.response.contentLength = b.length;
  r.response.add(b);
  await r.response.close();
}

class _GithubMock {
  _GithubMock(this.base);
  final String base;
  int webHits = 0;
  int apiHits = 0;
  String get latest => '$base/o/r/releases/latest';
  String get api => '$base/api/latest';
}

void main() {
  setUp(useTempHome);

  Future<_GithubMock> github({
    String? tag,
    int? web,
    int? apiStatus,
    String? apiTag,
  }) async {
    late final _GithubMock gh;
    final srv = await startServer((r) async {
      if (r.uri.path == '/o/r/releases/latest') {
        gh.webHits++;
        if (web != null) {
          r.response.statusCode = web;
        } else {
          r.response.statusCode = 302;
          r.response.headers.set(
            'location',
            tag == null
                ? '${gh.base}/o/r/releases'
                : '${gh.base}/o/r/releases/tag/$tag',
          );
        }
        await r.response.close();
      } else {
        gh.apiHits++;
        await respond(
          r,
          apiStatus == null || apiStatus == 200
              ? jsonEncode({'tag_name': apiTag ?? tag ?? 'v0.0.1'})
              : '{"message":"rate limit"}',
          status: apiStatus ?? 200,
        );
      }
    });
    addTearDown(() => srv.close(force: true));
    return gh = _GithubMock('http://127.0.0.1:${srv.port}');
  }

  Future<UpdateResult> check(_GithubMock gh, [String current = '1.0.0']) =>
      UpdateChecker.check(current, latestUrl: gh.latest, apiUrl: gh.api);

  group('UpdateChecker - finding latest release', () {
    test('a newer release is reported from web redirect alone', () async {
      final gh = await github(tag: 'v1.0.1');
      final r = await check(gh);
      expect(r.hasUpdate, isTrue);
      expect(r.version, '1.0.1');
      expect(r.failed, isFalse);
      expect(r.isDismissed, isFalse);
      expect(r.shouldShowDialog, isTrue);
      expect(gh.webHits, 1);
      expect(
        gh.apiHits,
        0,
        reason: 'REST API not needed when web redirect works',
      );
    });

    test('same or older release is not an update and not an error', () async {
      for (final tag in ['v1.0.0', 'v0.9.9', '1.0.0']) {
        final r = await check(await github(tag: tag));
        expect(r.hasUpdate, isFalse, reason: tag);
        expect(r.failed, isFalse, reason: tag);
      }
    });

    test('versions compare by semantic number, not by text', () async {
      expect(
        (await check(await github(tag: 'v1.10.0'), '1.9.0')).hasUpdate,
        isTrue,
      );
      expect(
        (await check(await github(tag: 'v1.9.0'), '1.10.0')).hasUpdate,
        isFalse,
      );
    });

    test('project with no release yet is not an error', () async {
      final gh = await github(tag: null);
      final r = await check(gh);
      expect(r.hasUpdate, isFalse);
      expect(r.failed, isFalse);
      expect(gh.apiHits, 0);
    });

    test('REST API is used if web release page does not answer', () async {
      final gh = await github(web: 404, apiTag: 'v1.0.1');
      final r = await check(gh);
      expect(r.version, '1.0.1');
      expect(r.failed, isFalse);
      expect(gh.apiHits, 1);
    });

    test('rate limited API does not block web redirect check', () async {
      final gh = await github(tag: 'v1.0.1', apiStatus: 403);
      expect((await check(gh)).version, '1.0.1');
    });

    test(
      'rate limited everywhere is reported as failure, never as up to date',
      () async {
        final gh = await github(web: 403, apiStatus: 403);
        final r = await check(gh);
        expect(r.hasUpdate, isFalse);
        expect(r.failed, isTrue);
        expect(r.error, contains('limiting requests'));
        expect(r.shouldShowDialog, isFalse);
      },
    );

    test('no connection at all is reported as a failure', () async {
      final r = await UpdateChecker.check(
        '1.0.0',
        latestUrl: 'http://127.0.0.1:1/o/r/releases/latest',
        apiUrl: 'http://127.0.0.1:1/api/latest',
      );
      expect(r.failed, isTrue);
      expect(r.error, 'no connection to GitHub');
    });
  });

  group('UpdateChecker - Dismissal handling', () {
    test('"Later" is stored in prefs.json for that specific version', () async {
      final gh = await github(tag: 'v1.0.1');
      await UpdateChecker.dismissVersion('1.0.1');

      final file = File('${AppStore.dir}/prefs.json');
      expect(jsonDecode(file.readAsStringSync()), {
        'dismissedUpdateVersion': '1.0.1',
      });
      expect(UpdateChecker.isDismissed('1.0.1'), isTrue);

      final r = await check(gh);
      expect(
        r.hasUpdate,
        isTrue,
        reason: 'still an update for status bar icon',
      );
      expect(r.isDismissed, isTrue);
      expect(r.shouldShowDialog, isFalse);

      final newer = await check(await github(tag: 'v1.0.2'));
      expect(newer.isDismissed, isFalse);
      expect(newer.shouldShowDialog, isTrue);
    });

    test('manual check clears dismissal flag', () async {
      await UpdateChecker.dismissVersion('1.0.1');
      await UpdateChecker.clearDismissed();
      expect(UpdateChecker.isDismissed('1.0.1'), isFalse);
      expect(
        (await check(await github(tag: 'v1.0.1'))).shouldShowDialog,
        isTrue,
      );
    });
  });
}
