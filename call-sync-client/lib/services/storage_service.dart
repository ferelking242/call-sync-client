import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recording.dart';

class StorageService {
  static const _keyServerUrl  = 'server_url';
  static const _keyUsername   = 'username';
  static const _keyPassword   = 'password';
  static const _keyToken      = 'auth_token';
  static const _keyDownloaded = 'downloaded_records_v2';

  // ── Remote config (GitHub raw) ────────────────────────────────────────────
  static const _remoteConfigUrl =
      'https://raw.githubusercontent.com/ferelking242/Callsync/main/server-config.json';

  static Future<Map<String, String>?> fetchRemoteConfig() async {
    try {
      final r = await http
          .get(Uri.parse(_remoteConfigUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        return {
          'url':      (data['url'] as String? ?? '').replaceAll(RegExp(r'/+$'), ''),
          'password': data['password'] as String? ?? 'admin123',
          'username': data['username'] as String? ?? 'admin',
        };
      }
    } catch (_) {}
    return null;
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  static Future<String> getServerUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyServerUrl) ?? '';
  }

  /// Stores URL without trailing slash.
  static Future<void> setServerUrl(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyServerUrl, v.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<String> getUsername() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyUsername) ?? 'admin';
  }

  static Future<void> setUsername(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyUsername, v);
  }

  static Future<String> getPassword() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyPassword) ?? 'admin123';
  }

  static Future<void> setPassword(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPassword, v);
  }

  static Future<String> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyToken) ?? '';
  }

  static Future<void> setToken(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyToken, v);
  }

  // ── Downloaded records registry ────────────────────────────────────────────

  static Future<List<DownloadedRecord>> getDownloadedRecords() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_keyDownloaded);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((j) => DownloadedRecord.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDownloadedRecord(DownloadedRecord rec) async {
    final p    = await SharedPreferences.getInstance();
    final list = await getDownloadedRecords();
    list.removeWhere((r) => r.serverId == rec.serverId);
    list.add(rec);
    await p.setString(_keyDownloaded, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<void> removeDownloadedRecord(int serverId) async {
    final p    = await SharedPreferences.getInstance();
    final list = await getDownloadedRecords();
    list.removeWhere((r) => r.serverId == serverId);
    await p.setString(_keyDownloaded, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<void> clearAllDownloads() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyDownloaded);
  }

  static Future<int> deleteAllLocalFilesAndRegistry() async {
    final records = await getDownloadedRecords();
    int deleted = 0;
    for (final r in records) {
      try {
        final f = File(r.localPath);
        if (f.existsSync()) { await f.delete(); deleted++; }
      } catch (_) {}
    }
    try {
      final dir = await getRecordingsDir();
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          await e.delete(recursive: true);
        }
      }
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyDownloaded);
    return deleted;
  }

  static Future<bool> isDownloaded(int serverId) async {
    final list = await getDownloadedRecords();
    return list.any((r) => r.serverId == serverId);
  }

  // ── Local file storage ─────────────────────────────────────────────────────

  static Future<Directory> getRecordingsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> getLocalPath(String filename) async {
    final dir = await getRecordingsDir();
    return '${dir.path}/$filename';
  }

  static Future<int> getLocalStorageBytes() async {
    final dir = await getRecordingsDir();
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
