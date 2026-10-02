import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'debug_log_native.dart';
import 'debug_log_path.dart';
import 'debug_log_preference_store.dart';

const String kDebugLoggingStorageKey = 'ui_debug_logging_enabled_v1';

// Match the native allowlists in pirate-core's debug_log.rs. Arbitrary panic
// metadata must not provide another route for exporting private payloads.
const _panicCategories = {
  'runtime_async_drop',
  'runtime_missing',
  'runtime_nested_block_on',
  'tor_pending_channel_drop',
  'time_overflow',
  'unknown',
};
const _panicSourceFiles = {
  'api.rs',
  'blocking.rs',
  'client.rs',
  'context.rs',
  'lib.rs',
  'mod.rs',
  'preemptive.rs',
  'runtime.rs',
  'scheduler.rs',
  'shutdown.rs',
  'state.rs',
  'time.rs',
};
const _privateFields = {
  'mnemonic',
  'seed',
  'passphrase',
  'password',
  'pin',
  'panic_pin',
  'duress_passphrase',
  'spending_key',
  'sapling_key',
  'orchard_key',
  'ironwood_key',
  'sapling_viewing_key',
  'orchard_viewing_key',
  'ironwood_viewing_key',
  'viewing_key',
  'extsk',
  'ovk',
  'ivk',
  'fvk',
  'private_key',
  'secret',
  'panic',
  'panic_location',
  'backtrace',
  'stack',
};
const _correlatingFields = {
  'wallet_id',
  'account_id',
  'key_id',
  'address',
  'addresses',
  'z_addresses',
  'address_id',
  'txid',
  'txids',
  'spent_txid',
  'pending_txid',
  'recent_txids',
  'last_seen_txids',
  'txid_prefix',
  'nullifier',
  'nullifiers',
  'nf',
  'cmu',
  'cmx',
  'cmx_prefix',
  'commitment',
  'memo',
  'memo_hex',
  'path',
  'cwd',
  'db_path',
  'endpoint',
  'url',
  'host',
  'server',
  'server_name',
  'tls_server_name',
  'tls_pin',
};
final _panicMetadataKey = RegExp(
  r'"panic(?:_|\\u005f)(?:category|source(?:_|\\u005f)(?:file|line))"\s*:',
  caseSensitive: false,
);
final _privateFieldAssignment = RegExp(
  '("?(?:${_privateFields.join('|')})"?'
  r'\s*[:=]\s*)("[^"\\]*(?:\\.[^"\\]*)*"|[^,}\n]+)',
  caseSensitive: false,
);
final _correlatingFieldAssignment = RegExp(
  '("?(?:${_correlatingFields.join('|')})"?'
  r'\s*[:=]\s*)("[^"\\]*(?:\\.[^"\\]*)*"|[^,}\n]+)',
  caseSensitive: false,
);

Object? _redactJsonValue(Object? value) {
  if (value is List) {
    return value.map(_redactJsonValue).toList();
  }
  if (value is! Map<String, dynamic>) return value;
  return value.map((key, metadata) {
    final Object? sanitized;
    final normalizedKey = key.toLowerCase();
    switch (normalizedKey) {
      case 'panic_category':
        sanitized = _panicCategories.contains(metadata) ? metadata : 'unknown';
      case 'panic_source_file':
        sanitized = _panicSourceFiles.contains(metadata) ? metadata : null;
      case 'panic_source_line':
        sanitized = metadata is int && metadata > 0 && metadata <= 0xffffffff
            ? metadata
            : null;
      default:
        if (_privateFields.contains(normalizedKey)) {
          sanitized = '[REDACTED_SECRET]';
        } else if (_correlatingFields.contains(normalizedKey)) {
          sanitized = '[REDACTED]';
        } else {
          sanitized = _redactJsonValue(metadata);
        }
    }
    return MapEntry(key, sanitized);
  });
}

class DebugLogController {
  DebugLogController._();

  static final _preferenceStore = DebugLogPreferenceStore.platform();
  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static Future<void> openLogFolder() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    final folder = File(await resolveDebugLogPath()).absolute.parent;
    await folder.create(recursive: true);
    final command = Platform.isWindows
        ? 'explorer.exe'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    final result = await Process.run(command, [folder.path]);
    // Explorer may return 1 after handing the folder to an existing process.
    if (result.exitCode != 0 && !(Platform.isWindows && result.exitCode == 1)) {
      throw StateError('Unable to open log folder');
    }
  }

  static Future<void> initialize() async {
    final enabled = await _readEnabled();
    _enabled = enabled;
    await setNativeDebugLoggingEnabled(enabled: enabled);
    if (!enabled) {
      await clearAllLogs();
    }
  }

  static Future<void> syncNativeState() async {
    await setNativeDebugLoggingEnabled(enabled: _enabled);
    if (!_enabled) {
      await clearNativeDebugLogs();
    }
  }

  static Future<void> setEnabled({required bool enabled}) async {
    await _preferenceStore.write(
      key: kDebugLoggingStorageKey,
      enabled: enabled,
    );
    await setNativeDebugLoggingEnabled(enabled: enabled);
    _enabled = enabled;
    if (!enabled) {
      await clearAllLogs();
    }
  }

  static Future<void> clearAllLogs() async {
    await clearNativeDebugLogs();
    final paths = await _candidateLogPaths();
    for (final path in paths) {
      await _deleteLogFamily(path);
      await _deleteRuntimeMarker(path);
    }
  }

  static String redactDebugLogText(String value) {
    // Logs are JSONL. Redact complete values so nested objects, arrays and
    // escaped field names cannot leak through a regex-only replacement.
    var text = value
        .split('\n')
        .map((line) {
          try {
            return jsonEncode(_redactJsonValue(jsonDecode(line)));
          } on FormatException {
            // A malformed panic entry cannot safely preserve arbitrary tail text.
            return _panicMetadataKey.hasMatch(line)
                ? '[REDACTED_MALFORMED_PANIC_EVENT]'
                : line;
          }
        })
        .join('\n');
    text = text.replaceAllMapped(
      _privateFieldAssignment,
      (match) => '${match[1]}"[REDACTED_SECRET]"',
    );
    text = text.replaceAllMapped(
      _correlatingFieldAssignment,
      (match) => '${match[1]}"[REDACTED]"',
    );
    text = text.replaceAll(
      RegExp(
        r'\b(?:zs1|ztestsapling1|zregtestsapling1|pirate1|pirate-test1|pirate-regtest1)[a-z0-9_-]{20,}\b',
        caseSensitive: false,
      ),
      '[REDACTED_ADDRESS]',
    );
    text = text.replaceAll(
      RegExp(r'\b(?:0x)?[0-9a-f]{64,}\b', caseSensitive: false),
      '[REDACTED_HEX]',
    );
    text = text.replaceAll(RegExp(r'[A-Za-z]:\\[^\s",}]+'), '[REDACTED_PATH]');
    text = text.replaceAll(
      RegExp(r'/(?:Users|home|var|private|tmp|data|storage)/[^\s",}]+'),
      '[REDACTED_PATH]',
    );
    return text;
  }

  static Future<File?> exportRedactedDebugLogFile() async {
    final sourcePath = await resolveDebugLogPath();
    final source = File(sourcePath);
    if (!source.existsSync()) {
      return null;
    }

    final redacted = redactDebugLogText(await source.readAsString());
    final tempDir = await getTemporaryDirectory();
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}pirate-debug-log-redacted.txt',
    );
    await target.writeAsString(redacted, flush: true);
    return target;
  }

  static Future<bool> hasDebugLog() async {
    final path = await resolveDebugLogPath();
    return File(path).existsSync();
  }

  static Future<bool> _readEnabled() async {
    return _preferenceStore.read(key: kDebugLoggingStorageKey);
  }

  static Future<Set<String>> _candidateLogPaths() async {
    final paths = <String>{await resolveDebugLogPath()};
    final envPath = Platform.environment['PIRATE_DEBUG_LOG_PATH'];
    if (envPath != null && envPath.trim().isNotEmpty) {
      paths.add(envPath);
    }

    final fallbackBase = Directory.current.path;
    if (Platform.isWindows) {
      for (final key in ['LOCALAPPDATA', 'APPDATA']) {
        final base = Platform.environment[key];
        if (base == null || base.isEmpty) continue;
        paths.add(
          _joinPath(base, [
            'Pirate',
            'PirateWallet',
            'data',
            'logs',
            'debug.log',
          ]),
        );
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      final home = Platform.environment['HOME'] ?? fallbackBase;
      paths.add(
        _joinPath(home, [
          'Library',
          'Application Support',
          'com.Pirate.PirateWallet',
          'logs',
          'debug.log',
        ]),
      );
    } else if (Platform.isLinux || Platform.isAndroid) {
      final home = Platform.environment['HOME'] ?? fallbackBase;
      final base =
          Platform.environment['XDG_DATA_HOME'] ??
          _joinPath(home, ['.local', 'share']);
      paths.add(_joinPath(base, ['piratewallet', 'logs', 'debug.log']));
    }

    return paths;
  }

  static Future<void> _deleteLogFamily(String path) async {
    for (final candidate in [
      path,
      for (var index = 1; index <= 10; index++) '$path.$index',
    ]) {
      try {
        final file = File(candidate);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  static Future<void> _deleteRuntimeMarker(String debugLogPath) async {
    try {
      final marker = File(
        '${File(debugLogPath).parent.path}${Platform.pathSeparator}runtime_session.marker',
      );
      if (marker.existsSync()) {
        marker.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  static String _joinPath(String base, List<String> parts) {
    var path = base;
    for (final part in parts) {
      if (part.isEmpty) continue;
      path = path.endsWith(Platform.pathSeparator)
          ? '$path$part'
          : '$path${Platform.pathSeparator}$part';
    }
    return path;
  }
}
