import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/callsync_api.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl  = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass    = false;
  bool _saving      = false;
  bool _testing     = false;
  bool _fetchingCfg = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _urlCtrl.text  = await StorageService.getServerUrl();
    _userCtrl.text = await StorageService.getUsername();
    _passCtrl.text = await StorageService.getPassword(); // 'admin123' by default
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteConfig() async {
    setState(() => _fetchingCfg = true);
    try {
      final cfg = await StorageService.fetchRemoteConfig();
      if (cfg == null) {
        _showSnack('Config distante inaccessible', isError: true);
        return;
      }
      setState(() {
        if (cfg['url']!.isNotEmpty)      _urlCtrl.text  = cfg['url']!;
        if (cfg['username']!.isNotEmpty) _userCtrl.text = cfg['username']!;
        _passCtrl.text = cfg['password'] ?? 'admin123';
        _testResult = null;
      });
      _showSnack('Config chargée depuis GitHub ✓');
    } finally {
      if (mounted) setState(() => _fetchingCfg = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ok = await context.read<SyncService>().connect(
        _urlCtrl.text.trim(),
        _userCtrl.text.trim(),
        _passCtrl.text.trim(),
      );
      if (mounted) {
        _showSnack(ok ? '✓ Connecté avec succès' : 'Connexion échouée', isError: !ok);
        if (ok) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final token = await CallSyncApi.login(
        _urlCtrl.text.trim(),
        _userCtrl.text.trim(),
        _passCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _testOk     = token != null;
          _testResult = token != null
              ? '✓ Serveur accessible — identifiants valides'
              : '✗ Connexion impossible. Vérifiez l\'URL et les identifiants.';
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          // ── Section titre serveur ────────────────────────────────────────
          _SectionLabel('Serveur'),
          const SizedBox(height: 12),

          // URL
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'URL du serveur',
              hintText: 'https://dazzling-gorgeous-aggregators--regav89124.replit.app',
              prefixIcon: const Icon(Icons.language),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
            onChanged: (_) => setState(() => _testResult = null),
          ),
          const SizedBox(height: 14),

          // Username
          TextField(
            controller: _userCtrl,
            decoration: InputDecoration(
              labelText: 'Nom d\'utilisateur',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          const SizedBox(height: 14),

          // Password
          TextField(
            controller: _passCtrl,
            obscureText: !_showPass,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              hintText: 'admin123',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          const SizedBox(height: 8),

          // Remote config button
          TextButton.icon(
            onPressed: _fetchingCfg ? null : _fetchRemoteConfig,
            icon: _fetchingCfg
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('Charger config depuis GitHub'),
          ),
          const SizedBox(height: 16),

          // Test result banner
          if (_testResult != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _testOk
                    ? const Color(0xFF22C55E).withOpacity(0.15)
                    : theme.colorScheme.errorContainer,
              ),
              child: Row(
                children: [
                  Icon(
                    _testOk ? Icons.check_circle_outline : Icons.error_outline,
                    color: _testOk ? const Color(0xFF22C55E) : theme.colorScheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_testResult!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: _testOk
                                ? const Color(0xFF16A34A)
                                : theme.colorScheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
          if (_testResult != null) const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Tester'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Connecter & sauvegarder'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ── Section stockage local ───────────────────────────────────────
          _SectionLabel('Stockage local'),
          const SizedBox(height: 12),

          _LocalStorageCard(),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: theme.colorScheme.primary));
  }
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
    final bytes   = await StorageService.getLocalStorageBytes();
    if (mounted) setState(() { _bytes = bytes; _count = records.length; });
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
          Row(
            children: [
              Icon(Icons.folder_open, color: theme.colorScheme.secondary),
              const SizedBox(width: 10),
              Text('$_count fichier(s) téléchargé(s)',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(StorageService.formatBytes(_bytes),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Effacer le registre local'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Effacer le stockage local'),
                    content: const Text(
                        'Tous les fichiers téléchargés seront supprimés de ce téléphone. '
                        'Les enregistrements restent sur le serveur.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Effacer'),
                      ),
                    ],
                  ),
                ) ?? false;
                if (!ok) return;
                if (mounted) {
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
