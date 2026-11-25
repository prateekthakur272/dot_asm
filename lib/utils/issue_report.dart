import 'dart:io' as io;

import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';

/// Builds the link that opens a new GitHub issue for this app, with a template and environment facts.
///
/// Only the app version and the operating system are included: no confidential file paths or settings.
/// The user sees and can edit everything on GitHub before submitting.
final class IssueReport {
  const IssueReport._();

  /// The text the issue starts with.
  static String body() {
    final os =
        '${io.Platform.operatingSystem} ${io.Platform.operatingSystemVersion}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return [
      '**What happened?**',
      '',
      '',
      '**What did you expect?**',
      '',
      '',
      '**Steps to reproduce**',
      '1. ',
      '2. ',
      '3. ',
      '',
      '---',
      '**Environment**',
      '- ${AppConfig.NAME} ${AppMetadata.full}',
      '- OS: $os',
      '',
    ].join('\n');
  }

  /// `https://github.com/<owner>/<repo>/issues/new?title=...&body=...`
  static Uri url({String title = ''}) => Uri.parse(AppConfig.ISSUES_URL)
      .replace(
        queryParameters: {if (title.isNotEmpty) 'title': title, 'body': body()},
      );
}
