import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/peer.dart';
import '../models/recording.dart';

class P2pApi {
  final PeerProfile peer;
  P2pApi(this.peer);

  Future<List<Recording>> getManifest() async {
    try {
      return await _getManifestDirect();
    } catch (directError) {
      if (peer.relay == null) rethrow;
      try {
        return await _getManifestRelay();
      } catch (relayError) {
        throw Exception(
            'Connexion P2P directe et relais Internet indisponibles: $relayError');
      }
    }
  }

  Future<List<Recording>> _getManifestDirect() async {
    final socket = await _open();
    try {
      final reader = _SocketReader(socket);
      await _send(socket, {'type': 'manifest'});
      final response = await reader.jsonLine();
      if (response['type'] != 'manifest') {
        throw Exception(response['error'] ?? 'Manifest pair invalide');
      }
      return _recordsFromFiles(response['files'] as List<dynamic>? ?? const []);
    } finally {
      await socket.close();
    }
  }

  Future<List<Recording>> _getManifestRelay() async {
    final response = await _relayRequest({'type': 'manifest'});
    if (response['type'] != 'manifest') {
      throw Exception(response['error'] ?? 'Manifest relais invalide');
    }
    return _recordsFromFiles(response['files'] as List<dynamic>? ?? const []);
  }

  List<Recording> _recordsFromFiles(List<dynamic> files) {
    return files.asMap().entries.map((entry) {
        final file = entry.value as Map<String, dynamic>;
        return Recording(
          id: _stableId(file['path'] as String? ?? '${entry.key}'),
          name: file['name'] as String? ?? '',
          size: (file['size'] as num?)?.toInt() ?? 0,
          sha256: file['sha256'] as String? ?? '',
          duration: (file['duration'] as num?)?.toDouble() ?? 0,
          uploadDate: _date(file['modifiedAt']),
          creationDate: _date(file['modifiedAt']),
          path: file['path'] as String? ?? '',
          deviceId: peer.id,
        );
      }).toList();
  }

  Future<void> downloadToFile(Recording record, String savePath,
      {int offset = 0}) async {
    try {
      await _downloadDirect(record, savePath, offset: offset);
    } catch (directError) {
      if (peer.relay == null) rethrow;
      try {
        await _downloadRelay(record, savePath);
      } catch (relayError) {
        throw Exception(
            'Téléchargement direct et relais Internet indisponibles: $relayError');
      }
    }
  }

  Future<void> _downloadDirect(Recording record, String savePath,
      {int offset = 0}) async {
    final socket = await _open();
    final tempPath = '$savePath.part';
    try {
      final existing = File(tempPath);
      final actualOffset = await existing.exists() ? await existing.length() : 0;
      // Never trust a stale caller offset: the part file is the source of
      // truth after a process death or a network switch.
      offset = actualOffset;
      final reader = _SocketReader(socket);
      await _send(socket, {
        'type': 'download',
        'path': record.path,
        'offset': offset,
      });
      final header = await reader.jsonLine();
      if (header['type'] != 'file') {
        throw Exception(header['error'] ?? 'Transfert pair refusé');
      }
      final total = (header['size'] as num?)?.toInt() ?? 0;
      final expectedHash = header['sha256'] as String? ?? record.sha256;
      if (offset + total != record.size) {
        throw Exception('Taille du fichier pair invalide pour ${record.name}');
      }
      final output = File(tempPath);
      if (offset == 0) {
        await output.writeAsBytes(const []);
      }
      final sink = output.openWrite(mode: FileMode.append);
      var remaining = total;
      while (remaining > 0) {
        final chunk = await reader.bytes(remaining > 64 * 1024
            ? 64 * 1024
            : remaining);
        sink.add(chunk);
        remaining -= chunk.length;
      }
      await sink.close();
      // The source sends the full-file hash even when only the tail is sent.
      // Hash the complete resumed part, not only the newly received bytes.
      final actual = await sha256.bind(File(tempPath).openRead()).first;
      if (actual.toString() != expectedHash) {
        await output.delete();
        throw Exception('SHA-256 invalide pour ${record.name}');
      }
      await output.rename(savePath);
    } finally {
      await socket.close();
    }
  }

  Future<bool> ping() async {
    try {
      final socket = await _open();
      try {
        final reader = _SocketReader(socket);
        await _send(socket, {'type': 'ping'});
        final response = await reader.jsonLine();
        return response['type'] == 'pong';
      } finally {
        await socket.close();
      }
    } catch (_) {
      if (peer.relay == null) rethrow;
      final response = await _relayRequest({'type': 'ping'});
      return response['type'] == 'pong';
    }
  }

  Future<void> _downloadRelay(Recording record, String savePath) async {
    final tempPath = '$savePath.part';
    final output = File(tempPath);
    var offset = await output.exists() ? await output.length() : 0;
    if (offset == 0) {
      await output.writeAsBytes(const []);
    }

    String expectedHash = record.sha256;
    while (offset < record.size) {
      final response = await _relayRequest({
        'type': 'download',
        'path': record.path,
        'offset': offset,
        'maxBytes': 256 * 1024,
      });
      if (response['type'] != 'file') {
        throw Exception(response['error'] ?? 'Transfert relais refusé');
      }
      final totalSize = (response['totalSize'] as num?)?.toInt() ?? 0;
      if (totalSize != record.size) {
        throw Exception('Taille du fichier pair invalide pour ${record.name}');
      }
      expectedHash = response['sha256'] as String? ?? expectedHash;
      final data = base64.decode(response['data'] as String? ?? '');
      if (data.isEmpty) throw const SocketException('Transfert relais interrompu');
      if (offset + data.length > record.size) {
        throw Exception('Données relais trop longues pour ${record.name}');
      }
      final sink = output.openWrite(mode: FileMode.append);
      sink.add(data);
      await sink.close();
      offset += data.length;
    }

    final actual = await sha256.bind(output.openRead()).first;
    if (actual.toString() != expectedHash) {
      await output.delete();
      throw Exception('SHA-256 invalide pour ${record.name}');
    }
    await output.rename(savePath);
  }

  Future<Map<String, dynamic>> _relayRequest(
      Map<String, dynamic> request) async {
    final relay = peer.relay;
    if (relay == null || relay.isEmpty) {
      throw const SocketException('Relais P2P non configuré');
    }
    final requestTimeout = request['type'] == 'download'
        ? const Duration(seconds: 130)
        : const Duration(seconds: 30);
    final response = await http
        .post(
          Uri.parse('${relay.replaceFirst(RegExp(r'/$'), '')}/p2p/client/request'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'source_id': peer.id,
            'secret': peer.secret,
            'request': request,
          }),
        )
        .timeout(requestTimeout);
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body is Map ? body['error'] ?? 'Relais indisponible' : 'Relais indisponible');
    }
    if (body is! Map<String, dynamic>) {
      throw Exception('Réponse relais invalide');
    }
    final result = body['response'];
    if (result is! Map<String, dynamic>) {
      throw Exception('Réponse P2P absente');
    }
    return result;
  }

  Future<Socket> _open() async {
    Socket? socket;
    Object? lastError;
    for (final host in peer.hosts) {
      try {
        socket = await Socket.connect(host, peer.port,
            timeout: const Duration(seconds: 15));
        break;
      } catch (error) {
        lastError = error;
      }
    }
    final connected = socket;
    if (connected == null) {
      throw SocketException('Pair indisponible: ${lastError ?? peer.host}');
    }
    connected.setOption(SocketOption.tcpNoDelay, true);
    final nonce = base64Url.encode(List<int>.from(
        List<int>.generate(32, (_) => Random.secure().nextInt(256))));
    final digest = Hmac(sha256, utf8.encode(peer.secret))
        .convert(utf8.encode(nonce));
    // CallSync signs the handshake with URL-safe Base64 without padding.
    // Using Digest.toString() here would send hex and fail authentication.
    final auth = base64Url.encode(digest.bytes).replaceAll('=', '');
    await _send(connected, {
      'type': 'hello',
      'peerId': peer.id,
      'nonce': nonce,
      'auth': auth,
    });
    final reader = _SocketReader(connected);
    final response = await reader.jsonLine();
    if (response['type'] != 'ready') {
      await connected.close();
      throw Exception(response['error'] ?? 'Pair non autorisé');
    }
    return connected;
  }

  static Future<void> _send(Socket socket, Map<String, dynamic> payload) async {
    socket.write('${jsonEncode(payload)}\n');
    await socket.flush();
  }

  static int _stableId(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return hash;
  }

  static String _date(dynamic value) {
    final millis = (value as num?)?.toInt();
    return millis == null
        ? DateTime.now().toIso8601String()
        : DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String();
  }
}

class _SocketReader {
  final Socket socket;
  final _iterator;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  _SocketReader(this.socket) : _iterator = StreamIterator<List<int>>(socket);

  Future<Map<String, dynamic>> jsonLine() async {
    final line = await _line();
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Réponse pair invalide');
    }
    return decoded;
  }

  Future<String> _line() async {
    while (true) {
      final bytes = _buffer.toBytes();
      final index = bytes.indexOf(10);
      if (index >= 0) {
        final line = utf8.decode(bytes.sublist(0, index));
        _buffer.clear();
        if (index + 1 < bytes.length) {
          _buffer.add(bytes.sublist(index + 1));
        }
        return line;
      }
      if (!await _iterator.moveNext()) {
        throw const SocketException('Connexion pair interrompue');
      }
      _buffer.add(_iterator.current);
    }
  }

  Future<Uint8List> bytes(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) {
        throw const SocketException('Transfert interrompu');
      }
      _buffer.add(_iterator.current);
    }
    final all = _buffer.toBytes();
    final result = Uint8List.fromList(all.sublist(0, count));
    _buffer.clear();
    if (count < all.length) _buffer.add(all.sublist(count));
    return result;
  }
}