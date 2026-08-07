import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../services/inference_service.dart';
import '../services/local_server_service.dart';
import '../services/node_discovery_service.dart';
import 'platform_capabilities.dart';

/// Adds the Erebrus AI menu-bar/system-tray icon on desktop platforms.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell>
    with TrayListener, WindowListener {
  static const _macOSTrayIcon = 'assets/icons/tray/tray_icon_template.png';
  static const _windowsTrayIcon = 'assets/icons/tray/tray_icon.ico';
  static const _linuxTrayIcon = 'assets/icons/tray/tray_icon.png';

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (!PlatformCapabilities.supportsTray) return;
    trayManager.addListener(this);
    windowManager.addListener(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);

      if (Platform.isMacOS) {
        await trayManager.setIcon(
          _macOSTrayIcon,
          isTemplate: true,
          iconSize: 18,
        );
      } else {
        await trayManager.setIcon(
          Platform.isWindows ? _windowsTrayIcon : _linuxTrayIcon,
        );
      }

      await trayManager.setToolTip('Erebrus AI — private on-device AI');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open', label: 'Open Erebrus AI'),
            MenuItem(key: 'hide', label: 'Hide window'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit Erebrus AI'),
          ],
        ),
      );
      _initialized = true;
      debugPrint('[Desktop] Erebrus AI tray ready');
    } on Object catch (error) {
      debugPrint('[Desktop] tray initialization failed: $error');
    }
  }

  @override
  void dispose() {
    if (PlatformCapabilities.supportsTray) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        unawaited(_showWindow());
      case 'hide':
        unawaited(windowManager.hide());
      case 'quit':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    if (_initialized) unawaited(windowManager.hide());
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    try {
      await InferenceService.instance.unload();
      await LocalServerService.instance.stop();
      await NodeDiscoveryService.instance.stop();
    } on Object catch (error) {
      debugPrint('[Desktop] shutdown cleanup failed: $error');
    } finally {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
