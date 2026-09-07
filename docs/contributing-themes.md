# Contributing wallet themes

Only the original Default theme ships initially. Additional themes become
available only after a maintainer reviews and merges their pull requests.

Themes are bundled with the app and reviewed through pull requests. Users select
them in **Settings > Theme > Wallet style**. New installations use **Default**;
the existing System, Light or Dark preference is independent of wallet style.
The toolbar brightness toggle changes only that preference.

## Theme contract

The theme system lives in `app/lib/design/themes/`:

- `wallet_palette.dart` defines semantic color roles as a Flutter `ThemeExtension`.
- `default_palette.dart` maps the original light/dark tokens without changing them.
- `theme_registry.dart` lists the selectable themes and their stable storage IDs.
- Each additional palette file defines both light and dark variants.

`PTheme.light(palette: ...)` and `PTheme.dark(palette: ...)` build Material
components from the same palette used by custom wallet widgets. New widgets
should read `WalletPalette.of(context)` within `build`, rather than hardcoding
colors. Previews should receive an explicit palette so they do not change the
application's active colors.

Existing widgets still use the `AppColors` compatibility API. The application
root synchronizes it with the selected style and resolved brightness. Theme
definitions must not mutate that API or the original `PColors` constants.

## Add a theme

1. Create `app/lib/design/themes/your_theme_palette.dart`. Start with
   `defaultLightPalette.copyWith(...)` and `defaultDarkPalette.copyWith(...)`.
   Override semantic roles in this file, not individual screens.
2. Define both variants, even if you prefer one brightness. Give primary,
   secondary and verification gradients suitable foreground colors.
3. Import the file into `theme_registry.dart` and add a `WalletTheme` entry to
   `WalletThemes.all`. Use a unique lowercase ID such as `ocean-teal`.
   IDs are stored on devices: do not rename them after release. Unknown or
   removed IDs fall back to Default.
4. Supply a short display name and description as localized callbacks, for example
   `nameBuilder: () => 'Ocean Teal'.tr` and `descriptionBuilder: () => 'Cool ocean colors'.tr`.
   Keep the literal translation keys in the registry so the audit can find them;
   callbacks resolve the current language when the labels are displayed.
   The settings list and previews
   discover registry entries automatically. Add their English strings to the
   runtime translation catalog using the translation workflow below.
5. Extend tests when adding roles or changing behavior. The shared registry tests
   automatically exercise each registered light/dark palette.

Example palette definition:

```dart
import 'package:flutter/material.dart';
import 'default_palette.dart';

final oceanDarkPalette = defaultDarkPalette.copyWith(
  gradientAStart: const Color(0xFF65DDD0),
  gradientAEnd: const Color(0xFF39B7AB),
  textOnAccent: const Color(0xFF071A18),
  focusRing: const Color(0xFF65DDD0),
);
```

This is a starting point, not a complete theme: also review secondary and
verification gradients, selection states and the light palette together.

After defining `oceanLightPalette` as well, register the pair in
`WalletThemes.all` (keeping `defaultTheme` first):

```dart
WalletTheme(
  id: 'ocean-teal',
  nameBuilder: () => 'Ocean Teal'.tr,
  descriptionBuilder: () => 'Cool ocean colors'.tr,
  light: oceanLightPalette,
  dark: oceanDarkPalette,
),
```

The registry imports the palette file and the runtime localization extension.
No screen, route or preference-provider changes are needed for a new theme.

## Review requirements

- Preserve wallet behavior, transaction information, branding and navigation.
  Theme PRs should not add theme-specific branches to wallet screens.
- Keep error, warning and success meanings recognizable. Preserve black-on-white
  QR output and the distinction between interactive and disabled controls.
- Aim for at least 4.5:1 contrast for normal text and 3:1 for large text and
  interactive indicators. Check text against every surface and both ends of
  gradients. Do not lower existing test thresholds to admit a theme.
- Verify selection, hover, keyboard focus, disabled controls, dialogs, inputs,
  notifications and transaction status indicators in both variants.
- Use bundled resources only. No runtime theme downloads, remote fonts, custom
  scripts or changes to wallet storage/network behavior belong in a theme.
- Keep theme names stable and credit any borrowed work. Include its source and
  compatible license. Artwork, typography and layout extensions require a
  separate shared contract and review; palette definitions cannot alter them.
- Include phone and desktop screenshots in both brightness modes, plus results
  at narrow widths and enlarged text. Preserve the default appearance.

## Validation

From the repository root:

```bash
bash scripts/test-flutter.sh test/design/wallet_themes_test.dart \
  test/design/input_decoration_theme_test.dart \
  test/design/scrollbar_theme_test.dart \
  test/features/settings/theme_preferences_test.dart \
  test/features/settings/theme_screen_test.dart
```

From `app/`:

```bash
dart run tool/audit_runtime_translations.dart --write
dart run tool/audit_runtime_translations.dart
flutter analyze --fatal-infos
```

See [the translation workflow](localization/TRANSLATION_WORKFLOW.md) for catalog
rules. Do not replace human translations with English text.

The theme screen tests can render screenshots to an absolute directory by setting
`PIRATE_UI_CAPTURE_DIR` and passing `--update-goldens` to the test wrapper. Set
`PIRATE_MATERIAL_ICONS_FONT` to Flutter's bundled Material Icons font for captures.
Generated screenshots are review artifacts and should not be added to the app's
asset bundle.

