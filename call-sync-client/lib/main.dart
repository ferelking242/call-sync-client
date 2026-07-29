import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/sync_service.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SyncService(),
      child: const CallSyncApp(),
    ),
  );
}

class CallSyncApp extends StatefulWidget {
  const CallSyncApp({super.key});
  @override
  State<CallSyncApp> createState() => _CallSyncAppState();
}

class _CallSyncAppState extends State<CallSyncApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrap();
    });
  }

  /// On first launch (no server URL saved), auto-fetch config from GitHub.
  /// Then reconnect if credentials are available.
  Future<void> _bootstrap() async {
    final url = await StorageService.getServerUrl();

    if (url.isEmpty) {
      // First launch — pull remote config
      final config = await StorageService.fetchRemoteConfig();
      if (config != null && config['url']!.isNotEmpty) {
        await StorageService.setServerUrl(config['url']!);
        await StorageService.setUsername(config['username'] ?? 'admin');
        // Only pre-fill password if none saved
        final saved = await StorageService.getPassword();
        if (saved.isEmpty) {
          await StorageService.setPassword(config['password'] ?? 'admin123');
        }
      }
    }

    // Auto-reconnect with saved credentials
    final savedUrl = await StorageService.getServerUrl();
    if (savedUrl.isNotEmpty && mounted) {
      context.read<SyncService>().reconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallSync',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: base.surface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(0, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(0, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
