import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/recording.dart';

class CallSyncApi {
  final String baseUrl;
  final String token;

  CallSyncApi({required String baseUrl, required this.token})
      : baseUrl = normalizeBaseUrl(baseUrl);

  static String normalizeBaseUrl(String rawUrl) {
    final url = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (url.isEmpty ||
        uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
          'Adresse invalide : utilisez une URL complète en http:// ou https://');
    }
    return url;
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type':  'application/json',
  };

  // ── Health ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> checkServer(String rawUrl) async {
    final url = normalizeBaseUrl(rawUrl);
    final r = await http.get(Uri.parse('$url/health'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw HttpException('Serveur HTTP ${r.statusCode}');
    }
    // A reachable health endpoint is enough to continue. Older server/proxy
    // responses may be HTTP 200 without a JSON body; rejecting those here
    // breaks connections that worked before health-response validation.
    try {
      final body = jsonDecode(_responseText(r));
      if (body is Map<String, dynamic>) return body;
    } on FormatException {
      // Ignore non-JSON HTTP 200 health bodies for compatibility.
    }
    return const {'status': 'healthy'};
  }

  Future<bool> checkHealth() async {
    try {
      await checkServer(baseUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<String> login(
      String rawUrl, String username, String password) async {
    final url = normalizeBaseUrl(rawUrl);
    final r = await http.post(
      Uri.parse('$url/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 15));
    final responseText = _responseText(r);
    dynamic body;
    try {
      body = jsonDecode(responseText);
    } on FormatException {
      throw HttpException(
          'Réponse de connexion non JSON (HTTP ${r.statusCode})');
    }
    if (r.statusCode != 200) {
      final message = body is Map<String, dynamic> ? body['error'] : null;
      throw HttpException(
          'Connexion refusée (${r.statusCode})${message == null ? '' : ': $message'}');
    }
    if (body is! Map<String, dynamic> || body['token'] is! String) {
      throw const HttpException('Réponse de connexion invalide');
    }
    return body['token'] as String;
  }

  static String _responseText(http.Response response) {
    return utf8.decode(response.bodyBytes).replaceFirst('\uFEFF', '').trim();
  }

  // ── Records ───────────────────────────────────────────────────────────────

  Future<List<Recording>> getRecords() async {
    final r = await http.get(Uri.parse('$baseUrl/records'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return (jsonDecode(r.body) as List)
        .map((j) => Recording.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ── Download ──────────────────────────────────────────────────────────────

  // Uses /download/{id} (not /stream): triggers server-side auto-delete after serving.
  Future<void> downloadToFile(int recordId, String savePath, {int offset = 0}) async {
    final headers = <String, String>{..._headers};
    if (offset > 0) headers['Range'] = 'bytes=$offset-';
    final r = await http.get(Uri.parse('$baseUrl/download/$recordId'), headers: headers)
        .timeout(const Duration(minutes: 5));
    if (r.statusCode != 200 && r.statusCode != 206) {
      throw Exception('HTTP ${r.statusCode}');
    }
    final file = File(savePath);
    if (r.statusCode == 206 && offset > 0) {
      await file.writeAsBytes(r.bodyBytes, mode: FileMode.append);
    } else {
      await file.writeAsBytes(r.bodyBytes);
    }
  }

  // ── Delete single record (server-side) ───────────────────────────────────

  Future<void> deleteRecord(int recordId) async {
    final r = await http.delete(Uri.parse('$baseUrl/record/$recordId'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 && r.statusCode != 204) throw Exception('HTTP ${r.statusCode}');
  }

  // ── Purge all records on server ───────────────────────────────────────────

  Future<Map<String, dynamic>> purgeAll() async {
    final r = await http.delete(Uri.parse('$baseUrl/purge-all'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ── Stream URL (for just_audio) ───────────────────────────────────────────

  String streamUrl(int recordId) => '$baseUrl/stream/$recordId';

  Map<String, String> get authHeaders => {'Authorization': 'Bearer $token'};

  // ── Delete-at-source commands ─────────────────────────────────────────────

  Future<void> requestDeleteAtSource(String deviceId, List<String> sha256List) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/delete-commands'),
        headers: _headers,
        body: jsonEncode({'device_id': deviceId, 'sha256_list': sha256List}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Endpoint may not exist — silently ignore
    }
  }
}
