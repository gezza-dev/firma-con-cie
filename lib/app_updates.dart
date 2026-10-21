// SPDX-License-Identifier: BSD-3-Clause
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const appVersion = '1.0.0';
const _repository = 'gezza-dev/cie-id-desktop';
final releaseEndpoint = Uri.https(
  'api.github.com',
  '/repos/$_repository/releases/latest',
);

enum UpdateState { available, current, unavailable }

class AppUpdate {
  const AppUpdate(this.state, {this.version, this.page});
  final UpdateState state;
  final String? version;
  final Uri? page;
}

List<int>? _version(String value) {
  final m = RegExp(r'^v?\.?([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+[0-9]+)?$')
      .firstMatch(value);
  if (m == null || value.length > 64) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
}

AppUpdate parseRelease(int status, String body, {String current = appVersion}) {
  // A private repository, missing release, rate limit or network failure is
  // unavailable, never evidence that the installed version is current.
  if (status != 200 || utf8.encode(body).length > 262144) {
    return const AppUpdate(UpdateState.unavailable);
  }
  try {
    final release = jsonDecode(body);
    if (release is! Map ||
        release['draft'] != false ||
        release['prerelease'] != false ||
        release['tag_name'] is! String ||
        release['html_url'] is! String) {
      return const AppUpdate(UpdateState.unavailable);
    }
    final tag = release['tag_name'] as String;
    final candidate = _version(tag), installed = _version(current);
    final page = Uri.tryParse(release['html_url'] as String);
    if (candidate == null ||
        installed == null ||
        page == null ||
        page.scheme != 'https' ||
        page.host != 'github.com' ||
        page.hasPort ||
        page.userInfo.isNotEmpty ||
        page.hasQuery ||
        page.hasFragment ||
        page.pathSegments.join('/') != '$_repository/releases/tag/$tag') {
      return const AppUpdate(UpdateState.unavailable);
    }
    for (var i = 0; i < 3; i++) {
      if (candidate[i] > installed[i]) {
        return AppUpdate(UpdateState.available, version: tag, page: page);
      }
      if (candidate[i] < installed[i]) {
        return const AppUpdate(UpdateState.current);
      }
    }
    return const AppUpdate(UpdateState.current);
  } on Object {
    return const AppUpdate(UpdateState.unavailable);
  }
}

Future<AppUpdate> checkAppUpdates() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    return await (() async {
      final request = await client.getUrl(releaseEndpoint);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'CIE-ID-Desktop/$appVersion',
      );
      final response = await request.close();
      final bytes = <int>[];
      if (response.statusCode != 200) {
        return const AppUpdate(UpdateState.unavailable);
      }
      await for (final part in response) {
        if (part.length > 262144 - bytes.length) {
          return const AppUpdate(UpdateState.unavailable);
        }
        bytes.addAll(part);
      }
      return parseRelease(response.statusCode, utf8.decode(bytes));
    })().timeout(const Duration(seconds: 12));
  } on Object {
    return const AppUpdate(UpdateState.unavailable);
  } finally {
    client.close(force: true);
  }
}
