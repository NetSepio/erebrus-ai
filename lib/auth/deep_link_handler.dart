import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_web_auth.dart';
import 'wallet_auth_controller.dart';

/// Routes `erebrusai://` callbacks — desktop PASETO auth and mobile Reown envelopes.
///
/// The custom platform channel is only implemented on Android; on iOS and macOS
/// Reown/AppKit handle the deep-link envelopes through their own plugins.
class DeepLinkHandler {
  static const _methodChannel = MethodChannel('com.erebrus.ai/methods');
  static const _eventChannel = EventChannel('com.erebrus.ai/events');

  static WalletAuthController? _auth;

  static bool get _useCustomChannel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void initListener() {
    if (!_useCustomChannel) return;
    try {
      _eventChannel.receiveBroadcastStream().listen(_onLink, onError: _onError);
    } catch (e) {
      debugPrint('[DeepLinkHandler] initListener $e');
    }
  }

  static void bind(WalletAuthController auth) {
    if (kIsWeb) return;
    _auth = auth;
  }

  static Future<void> checkInitialLink() async {
    if (!_useCustomChannel) return;
    try {
      final link = await _methodChannel.invokeMethod<String>('initialLink');
      if (link != null && link.isNotEmpty) await _onLink(link);
    } catch (e) {
      debugPrint('[DeepLinkHandler] checkInitialLink $e');
    }
  }

  static Future<void> _onLink(dynamic link) async {
    if (link == null) return;
    final url = link.toString();
    final auth = _auth;
    if (auth == null) {
      debugPrint('[DeepLinkHandler] auth not bound for $url');
      return;
    }

    if (DesktopWebAuth.isAuthCallback(url)) {
      await auth.handleWebAuthCallback(url);
      return;
    }

    final modal = auth.appKitModal;
    if (modal == null) {
      debugPrint('[DeepLinkHandler] unhandled link (no Reown session): $url');
      return;
    }
    final handled = await modal.dispatchEnvelope(url);
    if (!handled) {
      debugPrint('[DeepLinkHandler] Reown did not handle: $url');
    }
  }

  static void _onError(dynamic error) {
    debugPrint('[DeepLinkHandler] $error');
  }
}
