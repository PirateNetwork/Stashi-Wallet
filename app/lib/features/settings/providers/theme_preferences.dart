import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/app_secure_storage.dart';
import '../../../design/themes/theme_registry.dart';

/// Bundled styles approved through repository review. Override only in tests.
final walletThemesProvider = Provider<List<WalletTheme>>(
  (ref) => WalletThemes.all,
);

// Non-secret presentation preference, using the app's existing preference store.
final themePreferenceStoreProvider = Provider<ThemePreferenceStore>(
  (ref) => const ThemePreferenceStore(),
);

class ThemePreferenceStore {
  const ThemePreferenceStore();
  static const key = 'ui_theme_style_v1';
  Future<String?> read() => appSecureStorage.read(key: key);
  Future<void> write(String id) => appSecureStorage.write(key: key, value: id);
}

class WalletThemeNotifier extends Notifier<WalletTheme> {
  int _revision = 0;
  Future<void> _writes = Future.value();
  WalletTheme _saved = WalletThemes.defaultTheme;

  @override
  WalletTheme build() {
    final store = ref.read(themePreferenceStoreProvider);
    final revision = _revision;
    Future<void>(() async {
      try {
        final id = await store.read();
        if (ref.mounted && revision == _revision) {
          _saved = WalletThemes.resolve(
            id,
            themes: ref.read(walletThemesProvider),
          );
          state = _saved;
        }
      } catch (_) {
        // A presentation preference must not prevent opening the wallet.
      }
    });
    return WalletThemes.defaultTheme;
  }

  Future<void> select(String id) {
    final theme = WalletThemes.resolve(
      id,
      themes: ref.read(walletThemesProvider),
    );
    final revision = ++_revision;
    state = theme;
    final store = ref.read(themePreferenceStoreProvider);
    // Serialize writes so quick selections cannot persist in reverse order.
    final write = _writes.then((_) async {
      await store.write(theme.id);
      _saved = theme;
    });
    _writes = write.catchError((Object _) {});
    return write.catchError((Object error, StackTrace stack) {
      if (ref.mounted && revision == _revision) state = _saved;
      Error.throwWithStackTrace(error, stack);
    });
  }
}

final walletThemeProvider = NotifierProvider<WalletThemeNotifier, WalletTheme>(
  WalletThemeNotifier.new,
);
