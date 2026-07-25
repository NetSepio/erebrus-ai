import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/catalog_service.dart';
import 'auth/deep_link_handler.dart';
import 'auth/runtime_config.dart';
import 'auth/wallet_auth_controller.dart';
import 'org/org_state.dart';
import 'services/chat_service.dart';
import 'services/backend_probe_service.dart';
import 'services/model_download_service.dart';
import 'services/model_package_service.dart';
import 'services/node_discovery_service.dart';
import 'services/storage_service.dart';
import 'services/transcription_session_repository.dart';
import 'services/persona_service.dart';
import 'services/power_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeConfig.load();

  // Keep downloads / serving alive in the background and the screen on.
  PowerService.instance.initialize();

  // Re-hydrate chats and personas so the first screens have data.
  await ChatService.instance.load();
  await PersonaService.instance.load();

  // Restore the user-selected models directory (with macOS security-scoped
  // bookmark) before scanning for downloaded models.
  await StorageService.instance.loadCustomModelsDirectory();
  await ModelPackageService.instance.loadIndex();
  await TranscriptionSessionRepository.instance.load();

  final auth = WalletAuthController();
  final orgState = OrgState(auth: auth);
  await auth.initialize();
  DeepLinkHandler.bind(auth);
  DeepLinkHandler.initListener();
  DeepLinkHandler.checkInitialLink();

  runApp(ErebrusApp(auth: auth, orgState: orgState));

  // Scan existing downloads and start LAN discovery after the first frame
  // so heavy file/network work does not block the initial UI paint.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(BackendProbeService.instance.probe());
    // Refresh checksum-bearing asset metadata in the background. The
    // UI offers verified updates; large model files are never downloaded
    // silently on a metered or battery-constrained device.
    unawaited(CatalogService.fetch());
    unawaited(ModelDownloadService.instance.scanDownloads());
    unawaited(NodeDiscoveryService.instance.start());
  });
}
