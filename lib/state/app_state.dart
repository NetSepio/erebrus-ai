import 'package:flutter/widgets.dart';

import '../auth/entitlement_state.dart';
import '../services/model_download_service.dart';
import '../auth/user_org_invite.dart';
import '../auth/user_profile.dart';
import '../auth/wallet_auth_controller.dart';
import '../org/ai_org.dart';
import '../org/org_state.dart';
import '../org/shared_model.dart';
import '../services/local_server_service.dart';
import '../services/power_service.dart';

/// App-level state that wraps auth and org controllers for the existing UI.
///
/// The auth/org controllers remain the source of truth; this class listens to
/// them and exposes a flatter API so the screens don't have to manage multiple
/// notifiers.
class AppState extends ChangeNotifier {
  AppState({
    required this.auth,
    required this.orgState,
  }) {
    auth.addListener(_onAuthChanged);
    orgState.addListener(_onOrgChanged);
    _syncFromAuth();
  }

  final WalletAuthController auth;
  final OrgState orgState;

  bool signedIn = false;
  bool onboarded = false;
  int onboardingTargetTab = 0; // Tab the shell should open on after onboarding.

  // Local node / server mock state.
  bool serving = true;
  bool serveOnNetwork = true;
  bool startAtLogin = true;
  bool pauseOnLowBattery = true;

  // Chat header selections.
  String selectedModel = 'Qwen 3.5 0.8B';
  String selectedModelId = '';
  String selectedModelQuant = 'Q4_K_M';
  String selectedPersona = 'Concise Analyst';

  /// True when the currently selected model has been downloaded and is ready
  /// to chat with locally.
  bool get isSelectedModelReady =>
      selectedModelId.isNotEmpty &&
      ModelDownloadService.instance.isDownloaded(selectedModelId);

  String? get walletAddress => auth.walletAddress.isNotEmpty ? auth.walletAddress : null;
  String? get userId => auth.userId.isNotEmpty ? auth.userId : null;
  String? get role => auth.role.isNotEmpty ? auth.role : null;
  UserProfile? get userProfile => auth.userProfile;
  List<UserOrgInvite> get pendingInvites => auth.accountOrgInvites;
  EntitlementState get entitlement => auth.entitlement;

  List<AiOrg> get orgs => orgState.orgs;
  AiOrg? get selectedOrg => orgState.selectedOrg;
  List<SharedModel> get orgModels => orgState.orgModels;

  void _onAuthChanged() {
    _syncFromAuth();
    notifyListeners();
  }

  void _onOrgChanged() {
    notifyListeners();
  }

  void _syncFromAuth() {
    signedIn = auth.isAuthenticated;
  }

  /// Toggles signed-in state for tests / mock mode. In production the UI calls
  /// [auth.openSignIn()] directly.
  void signIn() {
    signedIn = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    signedIn = false;
    notifyListeners();
    try {
      await auth.signOut();
    } catch (e) {
      debugPrint('[AppState] auth.signOut error: $e');
    }
    signedIn = auth.isAuthenticated;
    notifyListeners();
  }

  void completeOnboarding() {
    onboarded = true;
    notifyListeners();
  }

  void setServing(bool v) {
    serving = v;
    PowerService.instance.setServing(v,
        label: v ? 'Serving on LAN' : 'Node paused');
    if (v) {
      LocalServerService.instance.start().catchError((e) {
        debugPrint('[AppState] server start failed: $e');
      });
    } else {
      LocalServerService.instance.stop().catchError((e) {
        debugPrint('[AppState] server stop failed: $e');
      });
    }
    notifyListeners();
  }

  void setServeOnNetwork(bool v) {
    serveOnNetwork = v;
    notifyListeners();
  }

  void setStartAtLogin(bool v) {
    startAtLogin = v;
    notifyListeners();
  }

  void setPauseOnLowBattery(bool v) {
    pauseOnLowBattery = v;
    notifyListeners();
  }

  void selectModel(String name, String quant, {String? id}) {
    selectedModel = name;
    selectedModelQuant = quant;
    if (id != null) selectedModelId = id;
    notifyListeners();
  }

  void selectPersona(String name) {
    selectedPersona = name;
    notifyListeners();
  }

  Future<void> sharePersonaToOrg(String personaId) async {
    await orgState.sharePersona(personaId);
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    orgState.removeListener(_onOrgChanged);
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
