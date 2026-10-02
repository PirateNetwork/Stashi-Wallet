import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/logging/debug_log_controller.dart';

void main() {
  test('export retains safe panic metadata and redacts raw diagnostics', () {
    final raw = jsonEncode({
      'id': 'log_rust_panic',
      'data': {
        'panic': 'seed=abandon "wallet-1" abandon',
        'panic_location': '/Users/alice/private/shutdown.rs:51:9',
        'backtrace': 'mnemonic=abandon abandon\n/Users/alice/wallet-1',
        'panic_category': 'runtime_async_drop',
        'panic_source_file': 'shutdown.rs',
        'panic_source_line': 51,
      },
    });

    final exported = DebugLogController.redactDebugLogText(raw);
    final data =
        (jsonDecode(exported) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    expect(data['panic_category'], 'runtime_async_drop');
    expect(data['panic_source_file'], 'shutdown.rs');
    expect(data['panic_source_line'], 51);
    for (final field in ['panic', 'panic_location', 'backtrace']) {
      expect(data[field], '[REDACTED_SECRET]');
    }
    for (final secret in ['abandon', 'alice', 'wallet-1']) {
      expect(exported, isNot(contains(secret)));
    }
  });

  test('export rejects arbitrary strings in panic metadata fields', () {
    final raw = jsonEncode({
      'panic_category': 'wallet-1 "abandon abandon"',
      'panic_source_file': '/Users/alice/shutdown.rs',
      'panic_source_line': 'seed=abandon',
    });

    final exported = DebugLogController.redactDebugLogText(raw);
    final metadata = jsonDecode(exported) as Map<String, dynamic>;
    expect(metadata['panic_category'], 'unknown');
    expect(metadata['panic_source_file'], isNull);
    expect(metadata['panic_source_line'], isNull);
    for (final secret in ['abandon', 'alice', 'wallet-1']) {
      expect(exported, isNot(contains(secret)));
    }
  });

  test('export bounds source lines to positive u32 integers', () {
    for (final value in [0, -1, 0x100000000, 51.5, '51', null]) {
      final raw = jsonEncode({'panic_source_line': value});
      final metadata = jsonDecode(
        DebugLogController.redactDebugLogText(raw),
      ) as Map<String, dynamic>;
      expect(metadata['panic_source_line'], isNull);
    }
    final metadata = jsonDecode(
      DebugLogController.redactDebugLogText(
        jsonEncode({'panic_source_line': 0xffffffff}),
      ),
    ) as Map<String, dynamic>;
    expect(metadata['panic_source_line'], 0xffffffff);
  });

  test('export redacts nested metadata values and escaped field names', () {
    const raw =
        r'{"data":[{"panic\u005fcategory":["runtime_async_drop","wallet-1"],"panic_source_file":{"allowed":"shutdown.rs","private":"alice"},"panic_source_line":[51,"abandon"]},{"PANIC_CATEGORY":"runtime_async_drop","panic":["private-payload",{"details":"secret-tail"}],"addresses":["private-address","private-address-tail"]}]}';
    final exported = DebugLogController.redactDebugLogText(raw);
    final data = (jsonDecode(exported) as Map<String, dynamic>)['data'] as List;
    final first = data[0] as Map<String, dynamic>;
    final second = data[1] as Map<String, dynamic>;
    expect(first['panic_category'], 'unknown');
    expect(first['panic_source_file'], isNull);
    expect(first['panic_source_line'], isNull);
    expect(second['PANIC_CATEGORY'], 'runtime_async_drop');
    expect(second['panic'], '[REDACTED_SECRET]');
    expect(second['addresses'], '[REDACTED]');
    for (final secret in [
      'wallet-1',
      'alice',
      'abandon',
      'private-payload',
      'secret-tail',
      'private-address',
    ]) {
      expect(exported, isNot(contains(secret)));
    }
  });

  test('malformed panic entries fail closed and preserve JSONL boundaries', () {
    const raw =
        '{"panic_source_line":["wallet-1",{"details":"abandon"}\n'
        '{"data":{"panic_category":"runtime_async_drop"}}\n'
        '{"panic\\u005fcategory":{"secret-tail":"alice"}\n';
    final exported = DebugLogController.redactDebugLogText(raw);
    final lines = exported.split('\n');
    expect(lines, hasLength(4));
    expect(lines[0], '[REDACTED_MALFORMED_PANIC_EVENT]');
    expect(lines[2], '[REDACTED_MALFORMED_PANIC_EVENT]');
    expect(lines[3], isEmpty);
    final data =
        (jsonDecode(lines[1]) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    expect(data['panic_category'], 'runtime_async_drop');
    for (final secret in ['wallet-1', 'abandon', 'alice', 'secret-tail']) {
      expect(exported, isNot(contains(secret)));
    }
  });

  test('export consumes escaped quotes in existing private JSON fields', () {
    final raw = jsonEncode({
      'wallet_id': 'wallet-1 "private-wallet-name"',
      'memo': 'memo "very private" text',
      'panic': 'unexpected "secret panic words"',
    });

    final exported = DebugLogController.redactDebugLogText(raw);
    final metadata = jsonDecode(exported) as Map<String, dynamic>;
    expect(metadata['wallet_id'], '[REDACTED]');
    expect(metadata['memo'], '[REDACTED]');
    expect(metadata['panic'], '[REDACTED_SECRET]');
    expect(exported, isNot(contains('private')));
    expect(exported, isNot(contains('secret panic words')));
  });
}
