import 'package:dio/dio.dart';

const String apiBaseUrl = 'https://audiobook-python.onrender.com';

Dio buildApiClient() {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );
  return dio;
}

final Dio apiClient = buildApiClient();
