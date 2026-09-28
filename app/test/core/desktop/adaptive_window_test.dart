import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pirate_wallet/core/desktop/adaptive_window.dart';

void main() {
  test('narrow portrait Linux displays open a usable portrait window', () {
    final spec = resolveDesktopWindowSpec(const Size(390, 844));

    expect(spec.initialSize, const Size(342, 776));
    expect(spec.minimumSize, const Size(320, 480));
  });

  test('wide desktop displays retain the normal desktop window', () {
    final spec = resolveDesktopWindowSpec(const Size(1920, 1080));

    expect(spec.initialSize, kDesktopPreferredWindowSize);
    expect(spec.minimumSize, kDesktopPreferredMinimumSize);
  });
}
