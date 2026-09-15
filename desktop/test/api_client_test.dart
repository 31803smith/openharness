import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:harness/api/api_client.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('machine request hits the local CLI proxy, not the backend, with no credential', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final path = Completer<String?>();
    final hadAuthHeader = Completer<bool>();
    final subscription = server.listen((request) async {
      path.complete(request.uri.path);
      hadAuthHeader.complete(request.headers.value('authorization') != null);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'machines': [
                {
                  'machineId': 'machine-1',
                  'computerId': '0123456789abcdef0123456789abcdef',
                  'authMode': 'remote',
                  'status': 'online',
                },
              ],
            },
          }),
        );
      await request.response.close();
    });

    try {
      final api = ApiClient(
        config: AppConfig(
          apiBaseUrl: 'http://unused.invalid',
          localCliBaseUrl: 'http://127.0.0.1:${server.port}',
        ),
        session: AuthSession(),
      );
      final machines = await api.machines();

      expect(await path.future, '/api/machines');
      expect(await hadAuthHeader.future, isFalse);
      expect(machines.single.machineId, 'machine-1');
      expect(machines.single.computerId, '0123456789abcdef0123456789abcdef');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  group('describeApiError', () {
    final options = RequestOptions(
      path: '/api/machines',
      receiveTimeout: const Duration(seconds: 30),
    );
    test('names the leg that failed instead of quoting Dio', () {
      expect(
        describeApiError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
            message:
                'The request took longer than 0:00:30.000000 to receive data.',
          ),
        ),
        'the local Harness service did not answer within 30s — the Harness '
        'backend is probably slow right now. Retry in a moment.',
      );
      expect(
        describeApiError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        ),
        startsWith('the local Harness service is not answering on its port.'),
      );
    });
    test(
      'passes the backend sentence the daemon forwarded straight through',
      () {
        expect(
          describeApiError(
            ApiException(
              'The Harness backend did not answer GET /api/machines within 20s. Try again in a moment.',
              status: 504,
            ),
          ),
          'The Harness backend did not answer GET /api/machines within 20s. Try again in a moment.',
        );
        expect(describeApiError(StateError('odd')), 'Bad state: odd');
      },
    );
  });

  test('only transient connection and gateway errors qualify for recovery', () {
    for (final status in [502, 503, 504]) {
      expect(
        isTransientApiError(ApiException('unavailable', status: status)),
        isTrue,
      );
    }
    for (final status in [400, 401, 403, 404]) {
      expect(
        isTransientApiError(ApiException('refused', status: status)),
        isFalse,
      );
    }
    final options = RequestOptions(path: '/api/machines');
    expect(
      isTransientApiError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      isTrue,
    );
    expect(
      isTransientApiError(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
      ),
      isFalse,
    );
    expect(isTransientApiError(StateError('invalid response')), isFalse);
  });
}
