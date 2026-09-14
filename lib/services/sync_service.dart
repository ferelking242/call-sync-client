import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../api/callsync_api.dart';
import '../api/p2p_api.dart';
import '../models/peer.dart';
import '../models/recording.dart';
import 'storage_service.dart';

enum SyncStatus { idle, connecting, syncing, downloading, done, error }

class SyncService extends ChangeNotifier {
  SyncStatus _status = SyncStatus.idle;
  String _statusMessage = '';
  List<Recording> _peerRecords = [];
  List<DownloadedRecord> _localRecords = [];
  double _downloadProgress = 0;
  int _downloadDone = 0;
  int _downloadTotal = 0;
  String? _lastError;
  final Set<int> _downloadingIds = {};
  P2pApi? _api;
  CallSyncApi? _serverApi;
  PeerProfile? _peer;
  Timer? _keepAliveTimer;
  bool _reconnectInFlight = false;

  SyncStatus get status => _status;
  String get statusMessage => _statusMessage;
  List<Recording> get records => _peerRecords;
  List<DownloadedRecord> get localRecords => _localRecords;
  double get downloadProgress => _downloadProgress;
  int get downloadDone => _downloadDone;
  int get downloadTotal => _downloadTotal;
  String? get lastError => _lastError;
  PeerProfile? get peer => _peer;
  bool get isConnected =>
      (_api != null || _serverApi != null) && _status != SyncStatus.error;
  bool get usingServer => _serverApi != null;
  String? get serverUrl => _serverApi?.baseUrl;
  bool get isDownloading => _status == SyncStatus.downloading;
  int get missingCount => _peerRecords.where((r) => !r.isDownloaded).length;
  int get downloadedCount => _peerRecords.where((r) => r.isDownloaded).length;
  Set<int> get downloadingIds => _downloadingIds;
  String? streamUrl(int _) => null;
  Map<String, String>? get authHeaders => null;

  Future<bool> connectServer({
    required String url,
    required String username,
    required String password,
  }) async {
    _setStatus(SyncStatus.connecting, 'Connexion au serveur…');
    final cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanUrl.isEmpty || username.trim().isEmpty || password.isEmpty) {
      _lastError = 'URL, nom d’utilisateur et mot de passe sont obligatoires';
      _setStatus(SyncStatus.error, 'Configuration serveur incomplète');
      return false;
    }

    try {
      await CallSyncApi.checkServer(cleanUrl);
      final token =
          await CallSyncApi.login(cleanUrl, username.trim(), password);
      _serverApi = CallSyncApi(baseUrl: cleanUrl, token: token);
      _api = null;
      _peer = null;
      await StorageService.setServerConfig(
        url: cleanUrl,
        username: username,
        password: password,
      );
      _lastError = null;
      await fetchRecords();
      if (_status == SyncStatus.error) {
        throw HttpException(_lastError ?? 'Lecture du serveur impossible');
      }
      return true;
    } catch (error) {
      _serverApi = null;
      _lastError = _describeError(error);
      _setStatus(SyncStatus.error, 'Serveur inaccessible — $_lastError');
      return false;
    }
  }

  Future<bool> connectPeer(PeerProfile profile) async {
    _setStatus(SyncStatus.connecting, 'Connexion au pair…');
    _peer = profile;
    await StorageService.setPeer(profile);
    _startKeepAlive();
    try {
      final api = P2pApi(profile);
      if (!await api.ping()) throw const SocketException('Pair indisponible');
      _api = api;
      _serverApi = null;
      _lastError = null;
      await refreshLocalRecords();
      await fetchRecords();
      return true;
    } catch (error) {
      _api = null;
      _lastError = error.toString();
      _setStatus(SyncStatus.error, 'Pair hors ligne');
      return false;
    }
  }

  Future<bool> reconnect() async {
    if (_reconnectInFlight) return false;
    _reconnectInFlight = true;
    try {
      final url = await StorageService.getServerUrl();
      final username = await StorageService.getServerUsername();
      final password = await StorageService.getServerPassword();
      final serverUrl = url.trim();
      if (serverUrl.isNotEmpty) {
        // A configured server is authoritative. Do not silently fall back to
        // P2P when it is unavailable; that created a confusing P2P spinner
        // while the user was trying to connect to the server.
        return await connectServer(
          url: serverUrl,
          username: username,
          password: password,
        );
      }

      // P2P pairing remains available through its explicit button in Settings.
      final profile = await StorageService.getPeer();
      if (profile != null) return await connectPeer(profile);
      return false;
    } finally {
      _reconnectInFlight = false;
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer ??= Timer.periodic(const Duration(minutes: 1), (_) async {
      final api = _api;
      if (_reconnectInFlight) return;
      if (_serverApi != null) {
        try {
          await fetchRecords();
        } catch (_) {
          await reconnect();
        }
        return;
      }
      if (_peer == null) return;
      if (api == null || _status == SyncStatus.error) {
        await reconnect();
        return;
      }
      try {
        if (!await api.ping()) throw const SocketException('Pair indisponible');
        await fetchRecords();
      } catch (error) {
        _api = null;
        _lastError = error.toString();
        _setStatus(SyncStatus.error, 'Pair hors ligne — reconnexion automatique');
      }
    });
  }

  Future<void> fetchRecords() async {
    final serverApi = _serverApi;
    final peerApi = _api;
    if (serverApi == null && peerApi == null) return;
    _setStatus(SyncStatus.syncing, 'Lecture du manifeste…');
    try {
      final records = serverApi != null
          ? await serverApi.getRecords()
          : await peerApi!.getManifest();
      await refreshLocalRecords();
      final byHash = {for (final record in _localRecords) record.sha256: record};
      for (final record in records) {
        final local = byHash[record.sha256];
        record.isDownloaded = local != null && File(local.localPath).existsSync();
        record.localPath = record.isDownloaded ? local!.localPath : null;
      }
      _peerRecords = records;
      _setStatus(SyncStatus.done, '${records.length} fichier(s) du pair');
      unawaited(_autoDownloadMissing());
    } catch (error) {
      _lastError = error.toString();
      _setStatus(SyncStatus.error, 'Manifest inaccessible');
    }
  }

  Future<void> refreshLocalRecords() async {
    _localRecords = await StorageService.getDownloadedRecords();
    notifyListeners();
  }

  Future<void> _autoDownloadMissing() async {
    final missing = _peerRecords.where((record) => !record.isDownloaded).toList();
    if (missing.isEmpty) return;
    _downloadTotal = missing.length;
    _downloadDone = 0;
    _downloadProgress = 0;
    _setStatus(SyncStatus.downloading, 'Synchronisation automatique…');
    for (final record in missing) {
      await downloadOne(record);
    }
    _setStatus(SyncStatus.done, 'Synchronisation terminée');
  }

  Future<void> downloadAllMissing() => _autoDownloadMissing();

  Future<void> downloadOne(Recording record) async {
    final serverApi = _serverApi;
    final peerApi = _api;
    if (serverApi == null && peerApi == null ||
        _downloadingIds.contains(record.id)) return;
    _downloadingIds.add(record.id);
    notifyListeners();
    try {
      final path = await StorageService.getLocalPath(record.name);
      final part = File('$path.part');
      final offset = await part.exists() ? await part.length() : 0;
      if (serverApi != null) {
        await serverApi.downloadToFile(record.id, part.path, offset: offset);
      } else {
        await peerApi!.downloadToFile(record, part.path, offset: offset);
      }
      if (await part.exists()) {
        if (await File(path).exists()) await File(path).delete();
        await part.rename(path);
      }
      record.isDownloaded = true;
      record.localPath = path;
      await StorageService.saveDownloadedRecord(DownloadedRecord(
        serverId: record.id,
        sha256: record.sha256,
        name: record.name,
        size: record.size,
        localPath: path,
        downloadedAt: DateTime.now(),
        deviceId: record.deviceId,
      ));
    } catch (error) {
      _lastError = error.toString();
    } finally {
      _downloadingIds.remove(record.id);
      _downloadDone++;
      _downloadProgress =
          _downloadTotal == 0 ? 0 : _downloadDone / _downloadTotal;
      await refreshLocalRecords();
      notifyListeners();
    }
  }

  Future<void> deleteLocal(Recording record) async {
    if (record.localPath != null) {
      try {
        await File(record.localPath!).delete();
      } catch (_) {}
    }
    await StorageService.removeDownloadedRecord(record.id);
    record.isDownloaded = false;
    record.localPath = null;
    await refreshLocalRecords();
    notifyListeners();
  }

  Future<void> deleteFromServer(Recording record) async {
    if (_serverApi != null) {
      await _serverApi!.deleteRecord(record.id);
      await deleteLocal(record);
      _peerRecords.removeWhere((item) => item.id == record.id);
      notifyListeners();
    } else {
      await deleteLocal(record);
    }
  }

  Future<Map<String, dynamic>?> purgeServer() async {
    if (_serverApi != null) {
      final result = await _serverApi!.purgeAll();
      await clearAllLocal();
      _peerRecords = [];
      notifyListeners();
      return result;
    }
    return {'deleted': 0, 'message': 'Aucun serveur de stockage'};
  }

  Future<int> clearAllLocal() async {
    final count = await StorageService.deleteAllLocalFilesAndRegistry();
    for (final record in _peerRecords) {
      record.isDownloaded = false;
      record.localPath = null;
    }
    await refreshLocalRecords();
    notifyListeners();
    return count;
  }

  Future<void> deleteAtSource(Recording record) async {
    if (_serverApi != null) {
      await _serverApi!.requestDeleteAtSource(record.deviceId, [record.sha256]);
    }
  }
  Future<void> purgeAllSourceFolders() async {}

  Future<void> unpair() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _api = null;
    _peer = null;
    await StorageService.clearPeer();
    _peerRecords = [];
    _setStatus(SyncStatus.idle, 'Aucun pair lié');
  }

  Future<void> disconnectServer() async {
    _serverApi = null;
    _peerRecords = [];
    await StorageService.clearServerConfig();
    _setStatus(SyncStatus.idle, 'Aucun serveur configuré');
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    super.dispose();
  }

  void _setStatus(SyncStatus status, String message) {
    _status = status;
    _statusMessage = message;
    notifyListeners();
  }

  String _describeError(Object error) {
    if (error is HttpException) return error.message;
    if (error is FormatException) return error.message;
    if (error is SocketException) {
      return 'Connexion réseau impossible (${error.osError?.message ?? error.message})';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}