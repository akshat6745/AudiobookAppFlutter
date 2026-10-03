import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// The backend (a GCP e2 instance). The only server the app talks to.
const _defaultApiBaseUrl = 'https://34.3.108.45.sslip.io';

/// Local-development override, e.g. for end-to-end testing against a backend
/// running on this machine:
///
/// ```
/// flutter run -d chrome --web-port=3000 \
///   --dart-define=API_BASE_URL=http://localhost:8077
/// ```
///
/// Empty in normal builds, in which case [_defaultApiBaseUrl] is used.
const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Backend base URL.
const String apiBaseUrl =
    _apiBaseUrlOverride == '' ? _defaultApiBaseUrl : _apiBaseUrlOverride;

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
  // it ONLY in debug builds and ONLY for our backend host so local testing
  // works. Release builds keep full certificate verification.
  if (kDebugMode && !kIsWeb) {
    final allowedHost = Uri.parse(apiBaseUrl).host;
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (cert, host, port) => host == allowedHost;
        return client;
      },
    );
  }

  return dio;
}

final Dio apiClient = buildApiClient();
