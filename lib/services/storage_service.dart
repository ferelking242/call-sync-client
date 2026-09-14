import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/peer.dart';
import '../models/recording.dart';

class StorageService {
  static const _keyPeer = 'paired_peer_v1';
  static const _keyDownloaded = 'downloaded_records_v2';
  static const _keyServerUrl = 'server_url_v1';
  static const _keyServerUsername = 'server_username_v1';
  static const _keyServerPassword = 'server_password_v1';

  // Can be overridden for a published build with:
  // --dart-define=CALLSYNC_SERVER_URL=https://your-server.replit.app
  static const defaultServerUrl = String.fromEnvironment(
    'CALLSYNC_SERVER_URL',
    defaultValue:
        'https://firsthand-wicked-fiber--noveb27831.replit.app',
  );
  static const defaultServerUsername = 'admin';
  static const defaultServerPassword = 'admin123';
  static const _legacyServerUrl =
      'vapid-pleasing-drawings--koyih59365.replit.app';
  static const _legacyDevServerUrl =
      '31b0ba36-e0f2-4a05-b3ce-726e52bd0b20-00-3qeptdt544x1d.riker.replit.dev';

  static Future<String> getServerUrl() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_keyServerUrl)?.trim();
    if (saved == null ||
        saved.isEmpty ||
        saved.contains(_legacyServerUrl) ||
        saved.contains(_legacyDevServerUrl)) {
      await p.setString(_keyServerUrl, defaultServerUrl);
      return defaultServerUrl;
    }
    return saved;
  }

  static Future<String> getServerUsername() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyServerUsername) ?? defaultServerUsername;
  }

  static Future<String> getServerPassword() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_keyServerPassword);
    if (saved == null || saved.isEmpty || saved == 'admin') {
      await p.setString(_keyServerPassword, defaultServerPassword);
      return defaultServerPassword;
    }
    return saved;
  }

  static Future<void> setServerConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyServerUrl, url.trim());
    await p.setString(_keyServerUsername, username.trim());
    await p.setString(_keyServerPassword, password);
  }

  static Future<void> clearServerConfig() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyServerUrl);
    await p.remove(_keyServerUsername);
    await p.remove(_keyServerPassword);
  }

  static Future<PeerProfile?> getPeer() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_keyPeer);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PeerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPeer(PeerProfile peer) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPeer, jsonEncode(peer.toJson()));
  }

  static Future<void> clearPeer() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyPeer);
  }

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
    final p = await SharedPreferences.getInstance();
    final list = await getDownloadedRecords();
    list.removeWhere((r) => r.serverId == rec.serverId);
    list.add(rec);
    await p.setString(
        _keyDownloaded, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<void> removeDownloadedRecord(int serverId) async {
    final p = await SharedPreferences.getInstance();
    final list = await getDownloadedRecords();
    list.removeWhere((r) => r.serverId == serverId);
    await p.setString(
        _keyDownloaded, jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  static Future<void> clearAllDownloads() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyDownloaded);
  }

  static Future<int> deleteAllLocalFilesAndRegistry() async {
    final records = await getDownloadedRecords();
    var deleted = 0;
    for (final r in records) {
      try {
        final file = File(r.localPath);
        if (file.existsSync()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {}
    }
    try {
      final dir = await getRecordingsDir();
      if (await dir.exists()) {
        await for (final entry in dir.list()) {
          await entry.delete(recursive: true);
        }
      }
    } catch (_) {}
    await clearAllDownloads();
    return deleted;
  }

  static Future<Directory> getRecordingsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> getLocalPath(String filename) async {
    final dir = await getRecordingsDir();
    final safeName = filename.replaceAll(RegExp(r'[/\\]'), '_');
    return '${dir.path}/$safeName';
  }

  static Future<int> getLocalStorageBytes() async {
    final dir = await getRecordingsDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}