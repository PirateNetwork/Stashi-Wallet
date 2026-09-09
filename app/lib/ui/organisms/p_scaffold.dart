import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop/windows_version.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import 'p_app_bar.dart';

/// Stashi Wallet Scaffold with custom titlebar for desktop
class PScaffold extends StatelessWidget {
  @visibleForTesting
  static bool debugShowDesktopTitleBar = false;

  const PScaffold({
    required this.body,
    this.title,
    this.appBar,
    this.drawer,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.useSafeArea = true,
    this.bodyMaxWidth,
    super.key,
  });

  final Widget body;
  final String? title;
  final PreferredSizeWidget? appBar;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool useSafeArea;

  /// Bounds task-focused forms while leaving dashboards and lists independent.
  final double? bodyMaxWidth;

  bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  bool get _isDesktop =>
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) && !_isTest;

  double _appBarHeight(BuildContext context) {
    final candidate = appBar;
    if (candidate == null) return 0;
    return candidate is PAppBar
        ? candidate.preferredHeightFor(context)
        : candidate.preferredSize.height;
  }

  @override
  Widget build(BuildContext context) {
    final boundedBody = bodyMaxWidth == null
        ? body
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bodyMaxWidth!),
              child: SizedBox(width: double.infinity, child: body),
            ),
          );
    final content = useSafeArea ? SafeArea(child: boundedBody) : boundedBody;
    final dismissibleContent = _KeyboardDismissArea(child: content);
    final useCustomTitleBar =
        debugShowDesktopTitleBar || (_isDesktop && shouldUseCustomTitleBar());

    if (useCustomTitleBar) {
      return Scaffold(
        backgroundColor: AppColors.backgroundBase,
        body: Column(
          children: [
            // Custom titlebar for desktop
            const PWindowTitleBar(title: 'Stashi Wallet'),

            if (appBar != null)
              SizedBox(height: _appBarHeight(context), child: appBar),
            // Main content
            Expanded(child: dismissibleContent),
          ],
        ),
        drawer: drawer,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    PreferredSizeWidget? resolvedAppBar = appBar;
    if (appBar != null) {
      final candidate = appBar!;
      final topPadding = MediaQuery.of(context).padding.top;
      final appBarHeight = candidate is PAppBar
          ? candidate.preferredHeightFor(context)
          : candidate.preferredSize.height;
      final height = appBarHeight + topPadding;
      resolvedAppBar = PreferredSize(
        preferredSize: Size.fromHeight(height),
        child: candidate,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: resolvedAppBar,
      body: dismissibleContent,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _KeyboardDismissArea extends StatelessWidget {
  const _KeyboardDismissArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// Custom titlebar for desktop with window controls
class PWindowTitleBar extends StatelessWidget {
  const PWindowTitleBar({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PSpacing.desktopTitlebarHeight,
      child: Container(
        height: PSpacing.desktopTitlebarHeight,
        decoration: BoxDecoration(
          color: AppColors.backgroundBase,
          border: Border(
            bottom: BorderSide(color: AppColors.borderSubtle, width: 1.0),
          ),
        ),
        child: Row(
          children: [
            // Draggable area
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: EdgeInsets.only(left: PSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: PTypography.labelLarge(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Window controls
            _WindowControls(),
          ],
        ),
      ),
    );
  }
}

/// Window control buttons (minimize, maximize, close)
class _WindowControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.remove,
          onPressed: () => unawaited(windowManager.minimize()),
        ),
        _WindowButton(
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          icon: Icons.close,
          onPressed: () => unawaited(windowManager.close()),
          isClose: true,
        ),
      ],
    );
  }
}

/// Individual window button
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: PSpacing.desktopTitlebarHeight,
          height: PSpacing.desktopTitlebarHeight,
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isClose ? AppColors.error : AppColors.hoverOverlay)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: PSpacing.iconSM,
            color: _isHovered && widget.isClose
                ? AppColors.textOnAccent
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
