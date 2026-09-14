import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/peer.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _saving = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final peer = await StorageService.getPeer();
    _urlCtrl.text = await StorageService.getServerUrl();
    _usernameCtrl.text = await StorageService.getServerUsername();
    _passwordCtrl.text = await StorageService.getServerPassword();
    if (peer != null) _codeCtrl.text = peer.encode();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  PeerProfile? _profile() => PeerProfile.decode(_codeCtrl.text);

  Future<void> _savePeer() async {
    final profile = _profile();
    if (profile == null) {
      _showSnack('Collez un code de liaison valide.', isError: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<SyncService>().connectPeer(profile);
    if (mounted) {
      setState(() => _saving = false);
      _showSnack(ok ? '✓ Pair lié avec succès' : 'Pair inaccessible',
          isError: !ok);
      if (ok) Navigator.pop(context);
    }
  }

  Future<void> _saveServer() async {
    setState(() => _saving = true);
    final ok = await context.read<SyncService>().connectServer(
          url: _urlCtrl.text,
          username: _usernameCtrl.text,
          password: _passwordCtrl.text,
        );
    if (mounted) {
      setState(() => _saving = false);
      _showSnack(
        ok ? '✓ Serveur connecté et fichiers synchronisés' : 'Serveur inaccessible',
        isError: !ok,
      );
      if (ok) Navigator.pop(context);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = context.watch<SyncService>().peer;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Paramètres',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionLabel('Serveur CallSync'),
          const SizedBox(height: 12),
          Text(
            'Connectez-vous au serveur pour recevoir les enregistrements '
            'depuis Internet ou votre réseau local.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adresse du serveur',
              hintText: 'https://exemple.replit.app',
              prefixIcon: Icon(Icons.cloud_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Nom d’utilisateur',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Masquer' : 'Afficher',
                icon: Icon(_showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveServer,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_sync_outlined),
              label: Text(_saving ? 'Connexion au serveur…' : 'Tester et synchroniser'),
            ),
          ),
          const SizedBox(height: 32),
          _SectionLabel('Liaison pair-à-pair'),
          const SizedBox(height: 12),
          Text(
            peer == null
                ? 'Liez ce téléphone au téléphone source une seule fois.'
                : 'Pair mémorisé : ${peer.name}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Code de liaison',
              hintText: 'Collez le code fourni par CallSync',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Le code contient l’adresse du pair et une clé d’accès. '
            'Il ne donne pas accès à un serveur de stockage central.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
           SizedBox(
             width: double.infinity,
             child: FilledButton.icon(
               onPressed: _saving ? null : _savePeer,
               icon: _saving
                   ? const SizedBox(
                       width: 18,
                       height: 18,
                       child: CircularProgressIndicator(
                           strokeWidth: 2, color: Colors.white))
                   : const Icon(Icons.sync_rounded),
               label: Text(_saving ? 'Connexion au pair…' : 'Lier & synchroniser'),
             ),
           ),
          const SizedBox(height: 32),
          _SectionLabel('Stockage local'),
          const SizedBox(height: 12),
          _LocalStorageCard(),
          const SizedBox(height: 20),
          if (peer != null)
            OutlinedButton.icon(
              onPressed: () async {
                await context.read<SyncService>().unpair();
                if (mounted) _showSnack('Pair supprimé de ce téléphone');
              },
              icon: const Icon(Icons.link_off),
              label: const Text('Oublier ce pair'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary));
}

class _LocalStorageCard extends StatefulWidget {
  @override
  State<_LocalStorageCard> createState() => _LocalStorageCardState();
}

class _LocalStorageCardState extends State<_LocalStorageCard> {
  int _bytes = 0;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await StorageService.getDownloadedRecords();
    final bytes = await StorageService.getLocalStorageBytes();
    if (mounted) setState(() {
      _bytes = bytes;
      _count = records.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.folder_open, color: theme.colorScheme.secondary),
            const SizedBox(width: 10),
            Text('$_count fichier(s) synchronisé(s)',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(StorageService.formatBytes(_bytes),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Effacer le stockage local'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error),
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                          title: const Text('Effacer le stockage local'),
                          content: const Text(
                              'Les fichiers seront supprimés de ce téléphone, '
                              'mais pas du dossier source.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Annuler')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Effacer')),
                          ],
                        )) ??
                    false;
                if (ok && mounted) {
                  await context.read<SyncService>().clearAllLocal();
                  await _load();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}