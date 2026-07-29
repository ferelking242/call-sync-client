import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../api/callsync_api.dart';
import '../models/recording.dart';
import 'storage_service.dart';

enum SyncStatus { idle, connecting, syncing, downloading, done, error }

class SyncService extends ChangeNotifier {
  SyncStatus _status        = SyncStatus.idle;
  String _statusMessage     = '';
  List<Recording> _serverRecords   = [];
  List<DownloadedRecord> _localRecords = [];
  double _downloadProgress  = 0.0;
  int _downloadDone         = 0;
  int _downloadTotal        = 0;
  String? _lastError;
  final Set<int> _downloadingIds = {};

  CallSyncApi? _api;

  SyncStatus get status           => _status;
  String get statusMessage        => _statusMessage;
  List<Recording> get records     => _serverRecords;
  List<DownloadedRecord> get localRecords => _localRecords;
  double get downloadProgress     => _downloadProgress;
  int get downloadDone            => _downloadDone;
  int get downloadTotal           => _downloadTotal;
  String? get lastError           => _lastError;
  bool get isConnected            => _api != null && _status != SyncStatus.error;
  bool get isDownloading          => _status == SyncStatus.downloading;
  int get missingCount            => _serverRecords.where((r) => !r.isDownloaded).length;
  int get downloadedCount         => _serverRecords.where((r) => r.isDownloaded).length;
  Set<int> get downloadingIds     => _downloadingIds;

  String? streamUrl(int id) => _api?.streamUrl(id);
  Map<String, String>? get authHeaders => _api?.authHeaders;

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<bool> connect(String serverUrl, String username, String password) async {
    _setStatus(SyncStatus.connecting, 'Connexion…');
    final url = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    await StorageService.setServerUrl(url);
    await StorageService.setUsername(username);
    await StorageService.setPassword(password);

    final token = await CallSyncApi.login(url, username, password);
    if (token == null) {
      _setStatus(SyncStatus.error, 'Identifiants incorrects ou serveur inaccessible');
      return false;
    }
    await StorageService.setToken(token);
    _api = CallSyncApi(baseUrl: url, token: token);
    _setStatus(SyncStatus.idle, 'Connecté');
    await refreshLocalRecords();
    await fetchRecords();
    return true;
  }

  Future<bool> reconnect() async {
    final url  = await StorageService.getServerUrl();
    final user = await StorageService.getUsername();
    final pass = await StorageService.getPassword();
    if (url.isEmpty) return false;
    return connect(url, user, pass);
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetchRecords() async {
    if (_api == null) return;
    _setStatus(SyncStatus.syncing, 'Chargement…');
    try {
      final records = await _api!.getRecords();
      await refreshLocalRecords();
      final localSha = _localRecords.map((r) => r.sha256).toSet();
      final localById = { for (final r in _localRecords) r.serverId: r };
      for (final r in records) {
        final local = localById[r.id] ?? _localRecords.where((lr) => lr.sha256 == r.sha256).firstOrNull;
        r.isDownloaded = local != null;
        if (local != null) r.localPath = local.localPath;
      }
      _serverRecords = records;
      _setStatus(SyncStatus.done, '${records.length} enregistrement(s)');
      unawaited(_autoDownloadMissing());
    } catch (e) {
      _setStatus(SyncStatus.error, 'Erreur: $e');
      _lastError = e.toString();
    }
  }

  Future<void> refreshLocalRecords() async {
    _localRecords = await StorageService.getDownloadedRecords();
    notifyListeners();
  }

  // ── Download all missing (parallel, cap 4) ────────────────────────────────

  Future<void> _autoDownloadMissing() async {
    if (_api == null) return;
    final missing = _serverRecords.where((r) => !r.isDownloaded).toList();
    if (missing.isEmpty) return;
    await _downloadList(missing);
  }

  Future<void> downloadAllMissing() async {
    if (_api == null) return;
    final missing = _serverRecords.where((r) => !r.isDownloaded).toList();
    if (missing.isEmpty) return;
    await _downloadList(missing);
  }

  Future<void> _downloadList(List<Recording> list) async {
    if (_api == null || list.isEmpty) return;
    _downloadTotal = list.length;
    _downloadDone  = 0;
    _downloadProgress = 0.0;
    _setStatus(SyncStatus.downloading, 'Téléchargement de ${list.length} fichier(s)…');

    const concurrency = 4;
    for (int i = 0; i < list.length; i += concurrency) {
      final batch = list.sublist(i, (i + concurrency).clamp(0, list.length));
      await Future.wait(batch.map(_downloadOne), eagerError: false);
    }

    await refreshLocalRecords();
    await fetchRecords();
  }

  /// Download a single recording; safe to call concurrently.
  Future<bool> downloadOne(Recording rec) async {
    if (_api == null || rec.isDownloaded || _downloadingIds.contains(rec.id)) {
      return false;
    }
    _downloadingIds.add(rec.id);
    notifyListeners();
    try {
      final path = await StorageService.getLocalPath(rec.name);
      await _api!.downloadToFile(rec.id, path);
      rec.isDownloaded = true;
      rec.localPath = path;
      await StorageService.saveDownloadedRecord(DownloadedRecord(
        serverId:    rec.id,
        sha256:      rec.sha256,
        name:        rec.name,
        size:        rec.size,
        localPath:   path,
        downloadedAt: DateTime.now(),
        deviceId:    rec.deviceId,
      ));
      return true;
    } catch (_) {
      return false;
    } finally {
      _downloadingIds.remove(rec.id);
      notifyListeners();
    }
  }

  Future<void> _downloadOne(Recording rec) async {
    _downloadingIds.add(rec.id);
    notifyListeners();
    try {
      final path = await StorageService.getLocalPath(rec.name);
      await _api!.downloadToFile(rec.id, path);
      rec.isDownloaded = true;
      rec.localPath = path;
      await StorageService.saveDownloadedRecord(DownloadedRecord(
        serverId:    rec.id,
        sha256:      rec.sha256,
        name:        rec.name,
        size:        rec.size,
        localPath:   path,
        downloadedAt: DateTime.now(),
        deviceId:    rec.deviceId,
      ));
    } catch (_) {
      // continue
    } finally {
      _downloadingIds.remove(rec.id);
      _downloadDone++;
      _downloadProgress = _downloadTotal > 0 ? _downloadDone / _downloadTotal : 0;
      notifyListeners();
    }
  }

  // ── Delete local ───────────────────────────────────────────────────────────

  Future<void> deleteLocal(Recording rec) async {
    if (rec.localPath != null) {
      try { await File(rec.localPath!).delete(); } catch (_) {}
    }
    await StorageService.removeDownloadedRecord(rec.id);
    rec.isDownloaded = false;
    rec.localPath = null;
    await refreshLocalRecords();
    notifyListeners();
  }

  // ── Delete from server ─────────────────────────────────────────────────────

  Future<void> deleteFromServer(Recording rec) async {
    if (_api == null) return;
    await _api!.deleteRecord(rec.id);
    _serverRecords.removeWhere((r) => r.id == rec.id);
    await deleteLocal(rec);
  }

  // ── Purge all server ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> purgeServer() async {
    if (_api == null) return null;
    final result = await _api!.purgeAll();
    _serverRecords.clear();
    notifyListeners();
    return result;
  }

  // ── Clear all local ───────────────────────────────────────────────────────

  Future<int> clearAllLocal() async {
    final count = await StorageService.deleteAllLocalFilesAndRegistry();
    for (final r in _serverRecords) {
      r.isDownloaded = false;
      r.localPath = null;
    }
    await refreshLocalRecords();
    notifyListeners();
    return count;
  }

  // ── Delete at source (single) ─────────────────────────────────────────────

  Future<void> deleteAtSource(Recording rec) async {
    if (_api == null) return;
    await _api!.requestDeleteAtSource(rec.deviceId, [rec.sha256]);
  }

  // ── Purge all source folders ──────────────────────────────────────────────
  // Sends delete-at-source commands for every recording, grouped by device.
  // The Kotlin recorder polls GET /delete-commands/{device_id} and deletes
  // the matching files from the monitored folder on its side.

  Future<void> purgeAllSourceFolders() async {
    if (_api == null) return;
    final byDevice = <String, List<String>>{};
    for (final r in _serverRecords) {
      byDevice.putIfAbsent(r.deviceId, () => []).add(r.sha256);
    }
    for (final entry in byDevice.entries) {
      await _api!.requestDeleteAtSource(entry.key, entry.value);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setStatus(SyncStatus s, String msg) {
    _status = s;
    _statusMessage = msg;
    notifyListeners();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
