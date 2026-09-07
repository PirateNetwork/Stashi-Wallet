import 'dart:io';

import '../../support/theme_test_fixtures.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/design/theme.dart';
import 'package:pirate_wallet/design/themes/theme_registry.dart';
import 'package:pirate_wallet/design/tokens/colors.dart';
import 'package:pirate_wallet/features/settings/providers/preferences_providers.dart';
import 'package:pirate_wallet/features/settings/providers/theme_preferences.dart';
import 'package:pirate_wallet/features/settings/screens/theme_screen.dart';
import 'package:pirate_wallet/features/settings/settings_screen.dart';

import '../../support/test_font_loader.dart';

class _Mode extends ThemeModeNotifier {
  _Mode(this.initial);
  final AppThemeMode initial;
  @override
  AppThemeMode build() => initial;
  @override
  Future<void> setThemeMode(AppThemeMode mode) async => state = mode;
}

class _Store extends ThemePreferenceStore {
  _Store(this.value);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String id) async => value = id;
}

class _App extends ConsumerWidget {
  const _App({this.settings = false});
  final bool settings;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(walletThemeProvider);
    final mode = ref.watch(appThemeModeProvider);
    final brightness = mode == AppThemeMode.light
        ? Brightness.light
        : Brightness.dark;
    AppColors.syncWithTheme(brightness, light: theme.light, dark: theme.dark);
    return MaterialApp(
      key: ValueKey((mode, theme.id)),
      debugShowCheckedModeBanner: false,
      theme: PTheme.light(palette: theme.light),
      darkTheme: PTheme.dark(palette: theme.dark),
      themeMode: mode.themeMode,
      themeAnimationDuration: Duration.zero,
      home: RepaintBoundary(
        key: const ValueKey('theme-capture'),
        child: settings
            ? const Scaffold(body: SettingsScreen(useScaffold: false))
            : const ThemeScreen(),
      ),
    );
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['PIRATE_UI_CAPTURE_DIR'];
  if (directory == null) return;
  await expectLater(
    find.byKey(const ValueKey('theme-capture')),
    matchesGoldenFile(Uri.file('$directory/$name.png')),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    await loadTestFont('Sora', 'assets/fonts/Sora/Sora.ttf');
    final icons = Platform.environment['PIRATE_MATERIAL_ICONS_FONT'];
    if (icons != null) await loadTestFont('MaterialIcons', icons);
  });
  tearDown(
    () => AppColors.syncWithTheme(
      Brightness.dark,
      light: WalletThemes.defaultTheme.light,
      dark: WalletThemes.defaultTheme.dark,
    ),
  );

  Future<_Store> pump(
    WidgetTester tester,
    Size size,
    String id,
    AppThemeMode mode, {
    double textScale = 1,
    bool settings = false,
    bool includeTestTheme = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _Store(id);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (includeTestTheme)
            walletThemesProvider.overrideWithValue(testWalletThemes),
          themePreferenceStoreProvider.overrideWithValue(store),
          appThemeModeProvider.overrideWith(() => _Mode(mode)),
          resolvedBiometricsEnabledProvider.overrideWith((ref) async => false),
          biometricAvailabilityProvider.overrideWith((ref) async => false),
        ],
        child: _App(settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  for (final id in ['default']) {
    for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
      testWidgets('$id ${mode.name} phone layout', (tester) async {
        await pump(tester, const Size(390, 844), id, mode);
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Test Teal'), findsNothing);
        expect(tester.takeException(), isNull);
        await capture(tester, 'themes-$id-${mode.name}-phone');
      });
    }
  }

  testWidgets('desktop cards share a row and selection preserves brightness', (
    tester,
  ) async {
    final store = await pump(
      tester,
      const Size(1280, 800),
      'default',
      AppThemeMode.dark,
      includeTestTheme: true,
    );
    final first = find.byKey(const ValueKey('theme-style-default'));
    final additional = find.byKey(const ValueKey('theme-style-test-teal'));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(additional).dy);
    await tester.tap(additional);
    await tester.pumpAndSettle();
    expect(store.value, 'test-teal');
    expect(
      Theme.of(tester.element(find.byType(ThemeScreen))).brightness,
      Brightness.dark,
    );
    expect(AppColors.backgroundBase, testWalletTheme.dark.backgroundBase);
    expect(tester.takeException(), isNull);
    // Test fixture is deliberately excluded from review screenshots.
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(store.value, 'test-teal');
    expect(AppColors.backgroundBase, testWalletTheme.light.backgroundBase);
  });

  testWidgets('default desktop layout', (tester) async {
    await pump(tester, const Size(1280, 800), 'default', AppThemeMode.dark);
    expect(find.text('Default'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'themes-default-dark-desktop');
  });

  testWidgets('small screen with large text remains scrollable', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(320, 640),
      'default',
      AppThemeMode.dark,
      textScale: 1.6,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-style-default')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings displays the selected wallet style and brightness', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(1280, 900),
      'default',
      AppThemeMode.dark,
      settings: true,
    );
    await tester.scrollUntilVisible(
      find.text('Default · Dark'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Default · Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'settings-default-dark-desktop');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
