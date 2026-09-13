import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/preferences_providers.dart';
import '../ffi/ffi_bridge.dart';
import '../i18n/arb_text_localizer.dart';
import 'biometric_auth.dart';

/// Reauthorize each user-initiated transaction before signing. Callers must
/// also check that their wallet and reviewed transaction have not changed.
Future<bool> authorizeTransaction(BuildContext context, WidgetRef ref) async {
  var biometricsEnabled = ref.read(biometricsEnabledProvider);
  if (!biometricsEnabled) {
    try {
      biometricsEnabled = await ref
          .read(biometricsEnabledProvider.notifier)
          .readPersistedValue();
    } catch (_) {
      // Preference failures require the passphrase, never implicit approval.
    }
  }
  if (!context.mounted) return false;
  if (biometricsEnabled) {
    try {
      final available = await BiometricAuth.isAvailable();
      if (!context.mounted) return false;
      if (available) {
        final authenticated = await BiometricAuth.authenticate(
          reason: 'Authenticate to send this transaction'.tr,
          biometricOnly: true,
        );
        if (authenticated) return context.mounted;
      }
    } on BiometricException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      // Unavailable or failed biometrics fall back to the app passphrase.
    }
  }
  if (!context.mounted) return false;
  final passphrase = await showDialog<String>(
    context: context,
    builder: (_) => const _TransactionPassphraseDialog(),
  );
  if (!context.mounted || passphrase == null || passphrase.isEmpty) {
    return false;
  }
  try {
    final valid = await FfiBridge.verifyAppPassphrase(passphrase);
    if (!context.mounted) return false;
    if (!valid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invalid passphrase.'.tr)));
    }
    return valid;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify passphrase.'.tr)),
      );
    }
    return false;
  }
}

class _TransactionPassphraseDialog extends StatefulWidget {
  const _TransactionPassphraseDialog();

  @override
  State<_TransactionPassphraseDialog> createState() =>
      _TransactionPassphraseDialogState();
}

class _TransactionPassphraseDialogState
    extends State<_TransactionPassphraseDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Passphrase is required.'.tr);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Confirm send'.tr),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter your passphrase to authorize this transaction.'.tr),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          keyboardType: TextInputType.visiblePassword,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          decoration: InputDecoration(
            hintText: 'Passphrase'.tr,
            errorText: _error,
          ),
          onSubmitted: (_) => _confirm(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('Cancel'.tr),
      ),
      TextButton(onPressed: _confirm, child: Text('Confirm'.tr)),
    ],
  );
}
