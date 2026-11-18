import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiFailure implements Exception {
  ApiFailure(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

String formatUserError(Object error) {
  if (error is ApiFailure) return error.message;
  if (error is StateError) return error.message;
  if (error is FormatException) return error.message;
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Tham số không hợp lệ.';
  }
  final raw = error.toString();
  return raw.startsWith('Exception: ') ? raw.substring(11) : raw;
}

abstract class ApiPort {
  String? token;
  Future<dynamic> request(String method, String path, {Json? body});
  void close();
}

class HttpApi implements ApiPort {
  HttpApi(String base, {http.Client? client})
    : base = Uri.parse(base.replaceFirst(RegExp(r'/+$'), '')),
      _client = client ?? http.Client() {
    if (!['http', 'https'].contains(this.base.scheme) ||
        this.base.host.isEmpty ||
        this.base.userInfo.isNotEmpty ||
        this.base.hasQuery ||
        this.base.hasFragment ||
        this.base.path.isNotEmpty && this.base.path != '/') {
      throw ArgumentError('API phải là origin HTTP(S), không có path/query.');
    }
    if (this.base.scheme != 'https' &&
        !['localhost', '127.0.0.1', '10.0.2.2'].contains(this.base.host)) {
      throw ArgumentError('Chỉ dùng HTTP cho local; demo cần HTTPS.');
    }
  }
  final Uri base;
  final http.Client _client;
  @override
  String? token;

  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    final uri = Uri.parse('${base.origin}$path');
    final request = http.Request(method, uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    // Render's free API can take about a minute to wake on the first call.
    final timeout = Duration(
      seconds: method == 'GET' && uri.path == '/api/v1/config' ? 75 : 15,
    );
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiFailure(
        0,
        'NETWORK_TIMEOUT',
        'API phản hồi quá ${timeout.inSeconds} giây. Hãy thử kết nối lại.',
      );
    } on http.ClientException {
      throw ApiFailure(
        0,
        'NETWORK_ERROR',
        'Không kết nối được tới API (${base.origin}). Kiểm tra kết nối mạng, URL API hoặc thử lại sau ít phút.',
      );
    }
    dynamic value;
    if (response.body.isNotEmpty) {
      try {
        value = jsonDecode(response.body);
      } on FormatException {
        final message = response.statusCode >= 500
            ? 'Máy chủ API đang tạm gián đoạn (HTTP ${response.statusCode}, phản hồi không phải JSON). Hãy thử lại sau ít phút.'
            : 'API không trả JSON hợp lệ (HTTP ${response.statusCode}). Kiểm tra lại địa chỉ API origin.';
        throw ApiFailure(response.statusCode, 'INVALID_RESPONSE', message);
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = value is Map ? value['error'] : null;
      final code = error is Map
          ? error['code']?.toString() ?? 'HTTP_ERROR'
          : 'HTTP_ERROR';
      var message = error is Map
          ? error['message']?.toString() ?? 'API lỗi (HTTP ${response.statusCode}).'
          : 'API lỗi (HTTP ${response.statusCode}).';
      if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after']?.trim();
        if (retryAfter != null && retryAfter.isNotEmpty) {
          message = '$message Hãy thử lại sau $retryAfter giây.';
        }
      }
      throw ApiFailure(response.statusCode, code, message);
    }
    return value;
  }

  @override
  void close() => _client.close();
}
