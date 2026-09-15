import 'package:dio/dio.dart';

import '../auth/auth_session.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../logging/http_log.dart';

/// Control-plane REST client. Every call here goes to the LOCAL `harness` CLI
/// (loopback, no credential — see CLAUDE.md's naming/architecture notes for why), which proxies to
/// the real backend using its own saved SSO session. This app never holds a bearer token itself.
/// Terminal bytes ride the local WS path (relayed transparently for non-local machines).
class ApiClient {
  final AppConfig config;
  final AuthSession session;
  late final Dio _dio = attachHttpLog(
    Dio(
      BaseOptions(
        baseUrl: config.localCliBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        // Let the API wrapper turn HTTP failures into short, user-facing
        // ApiExceptions. Transport failures still surface as DioExceptions.
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    ),
  );

  ApiClient({required this.config, required this.session});

  dynamic _unwrap(Response res) {
    final body = res.data;
    if (body is Map && body['success'] == true) {
      return body['data'];
    }
    final error = body is Map ? body['error'] : null;
    final serverMessage = error is Map ? error['message'] : null;
    throw ApiException(
      serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : 'Request failed (${res.statusCode})',
      status: res.statusCode,
    );
  }

  // -- auth (proxied by the local CLI — no credential on this leg) --
  Future<Map<String, dynamic>?> me() async {
    final res = await _dio.get('/api/auth/me');
    return _unwrap(res) as Map<String, dynamic>?;
  }

  // -- machines (control plane, proxied by the local CLI) --
  Future<List<Machine>> machines() async {
    final res = await _dio.get('/api/machines');
    final data = _unwrap(res) as Map<String, dynamic>;
    final list = data['machines'] as List<dynamic>? ?? [];
    return list
        .map((e) => Machine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String?> renameMachine({
    required String machineId,
    required String name,
  }) async {
    final res = await _dio.patch(
      '/api/machines/$machineId',
      data: {'name': name},
      options: Options(headers: {'x-adapter-local': '1'}),
    );
    final data = _unwrap(res) as Map<String, dynamic>;
    return data['name'] as String?;
  }

  Future<void> deleteMachine({required String machineId}) async {
    final res = await _dio.delete(
      '/api/machines/$machineId',
      options: Options(headers: {'x-adapter-local': '1'}),
    );
    _unwrap(res);
  }
}

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});
  @override
  String toString() => message;
}

bool isUnauthorizedError(Object error) =>
    error is DioException && error.response?.statusCode == 401 ||
    error is ApiException && error.status == 401;

/// The local daemon can answer normally while its separate backend request fails.
/// Those gateway errors need recovery just as a broken loopback connection does.
bool isTransientApiError(Object error) {
  if (error is ApiException) {
    return const {502, 503, 504}.contains(error.status);
  }
  return error is DioException &&
      const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(error.type);
}

/// The sentence a failed local-CLI call earns on an error strip. A raw
/// `DioException` is a paragraph about `RequestOptions.receiveTimeout` — true,
/// and useless to the person reading it: what they need is which leg failed.
/// The daemon not listening, the daemon not answering (it proxies to the
/// backend, so that is nearly always the backend being slow), or the backend
/// answering with a sentence of its own, which the daemon forwards verbatim.
String describeApiError(Object error) {
  if (error is ApiException) return error.message;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
        return 'the local Harness service is not answering on its port. '
            'It usually restarts on its own; retry in a moment.';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        final limit = error.requestOptions.receiveTimeout?.inSeconds;
        return 'the local Harness service did not answer'
            '${limit == null ? '' : ' within ${limit}s'} — the Harness '
            'backend is probably slow right now. Retry in a moment.';
      case DioExceptionType.badResponse:
        return 'the local Harness service answered '
            '${error.response?.statusCode ?? 'with an error'}.';
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return error.message ?? error.error?.toString() ?? 'request failed';
    }
  }
  return '$error';
}
