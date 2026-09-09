/// Settings-only selection for bundled wallet themes and brightness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/arb_text_localizer.dart';
import '../../../design/themes/theme_registry.dart';
import '../../../design/themes/wallet_palette.dart';
import '../../../design/tokens/spacing.dart';
import '../../../ui/organisms/p_app_bar.dart';
import '../../../ui/organisms/p_scaffold.dart';
import '../providers/preferences_providers.dart';
import '../providers/theme_preferences.dart';

class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(walletThemeProvider);
    final available = ref.watch(walletThemesProvider);
    final mode = ref.watch(appThemeModeProvider);
    final theme = Theme.of(context);

    Future<void> save(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save your theme. Please try again.'.tr),
            ),
          );
        }
      }
    }

    return PScaffold(
      bodyMaxWidth: 920,
      title: 'Theme'.tr,
      appBar: PAppBar(
        title: 'Theme'.tr,
        subtitle: 'Make Stashi feel like yours'.tr,
        showBackButton: true,
        showThemeToggle: false,
      ),
      body: SingleChildScrollView(
        padding: PSpacing.screenPadding(MediaQuery.sizeOf(context).width),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance'.tr, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Choose when to use light or dark colors.'.tr,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AppThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AppThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_outlined),
                        label: Text('System'.tr),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined),
                        label: Text('Light'.tr),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'.tr),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (selection) => save(
                      () => ref
                          .read(appThemeModeProvider.notifier)
                          .setThemeMode(selection.single),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text('Wallet style'.tr, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Every style includes light and dark colors.'.tr,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth >= 640 && available.length > 1
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final definition in available)
                          SizedBox(
                            width: width,
                            child: _StyleCard(
                              definition: definition,
                              selected: selected.id == definition.id,
                              onTap: () => save(
                                () => ref
                                    .read(walletThemeProvider.notifier)
                                    .select(definition.id),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.definition,
    required this.selected,
    required this.onTap,
  });
  final WalletTheme definition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: definition.name,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('theme-style-${definition.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: _PalettePreview(palette: definition.light),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PalettePreview(palette: definition.dark),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        definition.name,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 22,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(definition.description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explicit palettes keep previews independent of the active app theme.
class _PalettePreview extends StatelessWidget {
  const _PalettePreview({required this.palette});
  final WalletPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    height: 104,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: palette.backgroundBase,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: palette.borderStrong),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: palette.gradientAStart,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 5,
                color: palette.textTertiary.withValues(alpha: .4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(width: 58, height: 8, color: palette.textPrimary),
        const Spacer(),
        Container(
          height: 18,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: palette.gradientA),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ],
    ),
  );
}
