import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/deep_link_handler.dart';
import 'auth/runtime_config.dart';
import 'auth/wallet_auth_controller.dart';
import 'org/org_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeConfig.load();

  final auth = WalletAuthController();
  final orgState = OrgState(auth: auth);
  await auth.initialize();
  DeepLinkHandler.bind(auth);
  DeepLinkHandler.initListener();
  DeepLinkHandler.checkInitialLink();

  runApp(ErebrusApp(auth: auth, orgState: orgState));
}
