import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Backends the app can talk to. Switched from the Profile screen at
/// runtime; the choice is persisted in SharedPreferences.
enum BackendChoice {
  onrender('https://audiobook-python.onrender.com', 'OnRender'),
  northflank('https://p01--audiobookpython--npptgqlk6767.code.run', 'Northflank');

  const BackendChoice(this.url, this.label);

  final String url;
  final String label;

  static BackendChoice fromKey(String? key) {
    if (key == null) return BackendChoice.onrender;
    return BackendChoice.values.firstWhere(
      (b) => b.name == key,
      orElse: () => BackendChoice.onrender,
    );
  }
}

const _backendPrefKey = 'selected_backend';

BackendChoice _current = BackendChoice.onrender;

/// Local-development override, e.g. for end-to-end testing against a backend
/// running on this machine:
///
/// ```
/// flutter run -d chrome --web-port=3000 \
///   --dart-define=API_BASE_URL=http://localhost:8077
/// ```
///
/// Empty in normal builds, in which case the persisted [BackendChoice] wins.
const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Current backend base URL. Read this at call-time (not as a const) so that
/// switching the backend at runtime is reflected immediately in URL builders.
String get apiBaseUrl =>
    _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : _current.url;

BackendChoice get currentBackend => _current;

Dio buildApiClient() {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // DEBUG-ONLY: on networks with a TLS-inspecting proxy (e.g. Cloudflare Zero
  // Trust / a corporate VPN), the backend cert is re-signed by a private CA the
  // emulator's Dart TLS stack doesn't trust → CERTIFICATE_VERIFY_FAILED. Accept
  // it ONLY in debug builds and ONLY for our known backend hosts so local
  // testing works. Release builds keep full certificate verification.
  if (kDebugMode && !kIsWeb) {
    final allowedHosts = {
      for (final b in BackendChoice.values) Uri.parse(b.url).host,
    };
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (cert, host, port) => allowedHosts.contains(host);
        return client;
      },
    );
  }

  return dio;
}

final Dio apiClient = buildApiClient();

/// Load the persisted backend choice from SharedPreferences. Call once
/// during app bootstrap, before any network request fires.
Future<void> loadStoredBackend() async {
  final prefs = await SharedPreferences.getInstance();
  _current = BackendChoice.fromKey(prefs.getString(_backendPrefKey));
  apiClient.options.baseUrl = apiBaseUrl;
}

/// Switch the active backend and persist the choice. Mutates the shared
/// Dio instance's baseUrl so existing api wrappers pick up the new host
/// on their next request — no app restart required.
Future<void> setBackend(BackendChoice choice) async {
  _current = choice;
  apiClient.options.baseUrl = apiBaseUrl;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_backendPrefKey, choice.name);
}
