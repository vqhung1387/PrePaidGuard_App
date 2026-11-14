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
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    ).timeout(const Duration(seconds: 15));
    dynamic value;
    if (response.body.isNotEmpty) {
      try {
        value = jsonDecode(response.body);
      } on FormatException {
        throw ApiFailure(
          response.statusCode,
          'INVALID_RESPONSE',
          'API không trả JSON hợp lệ.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = value is Map ? value['error'] : null;
      throw ApiFailure(
        response.statusCode,
        error is Map ? error['code']?.toString() ?? 'HTTP_ERROR' : 'HTTP_ERROR',
        error is Map ? error['message']?.toString() ?? 'API lỗi.' : 'API lỗi.',
      );
    }
    return value;
  }

  @override
  void close() => _client.close();
}
