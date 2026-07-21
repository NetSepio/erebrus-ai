import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../services/persona_service.dart';
import '../data/mock_data.dart';

/// App-level state that wraps auth and org controllers for the existing UI.
///
/// The auth/org controllers remain the source of truth; this class listens to
/// them and exposes a flatter API so the screens don't have to manage multiple
/// notifiers.
class AppState extends ChangeNotifier {
  AppState({required this.auth, required this.orgState}) {
    auth.addListener(_onAuthChanged);
    orgState.addListener(_onOrgChanged);
    LocalServerService.instance.addListener(_onServerChanged);
    _syncFromAuth();
    unawaited(_loadLocalSettings());
  }

  final WalletAuthController auth;
  final OrgState orgState;

  bool signedIn = false;
  bool localSettingsLoaded = false;
  bool onboarded = false;
  int onboardingTargetTab = 0; // Tab the shell should open on after onboarding.

  bool serving = LocalServerService.instance.isRunning;

  // Chat header selections.
  String selectedModel = 'Select model';
  String selectedModelId = '';
  String selectedModelQuant = 'LOCAL';
  String selectedPersonaId = 'default';
  MockPersona get selectedPersonaConfig =>
      PersonaService.instance.byId(selectedPersonaId) ??
      PersonaService.instance.defaultPersona;
  int? responseTokenOverride;
  int get responseTokenLimit =>
      Platform.isAndroid || Platform.isIOS ? 1792 : 4096;
  int get maxResponseTokens =>
      responseTokenOverride ?? selectedPersonaConfig.maxTokens;
  MockPersona get effectivePersonaConfig =>
      selectedPersonaConfig.copyWith(maxTokens: maxResponseTokens);
  String get selectedPersona => selectedPersonaConfig.name;

  /// True when the currently selected model has been downloaded and is ready
  /// to chat with locally.
  bool get isSelectedModelReady =>
      selectedModelId.isNotEmpty &&
      ModelDownloadService.instance.isDownloaded(selectedModelId);

  String? get walletAddress =>
      auth.walletAddress.isNotEmpty ? auth.walletAddress : null;
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

  void _onServerChanged() {
    serving = LocalServerService.instance.isRunning;
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
    unawaited(_persistOnboardingCompletion());
  }

  Future<void> _persistOnboardingCompletion() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('onboarding_complete', true);
  }

  Future<void> setServing(bool v) async {
    serving = v;
    notifyListeners();
    await PowerService.instance.setServing(
      v,
      label: v ? 'Serving on LAN' : 'Node paused',
    );
    try {
      if (v) {
        await LocalServerService.instance.start();
      } else {
        await LocalServerService.instance.stop();
      }
    } catch (e) {
      if (v) {
        debugPrint('[AppState] server start failed: $e');
      } else {
        debugPrint('[AppState] server stop failed: $e');
      }
    } finally {
      serving = LocalServerService.instance.isRunning;
      notifyListeners();
    }
  }

  Future<void> setMaxResponseTokens(int? value) async {
    responseTokenOverride = value?.clamp(128, responseTokenLimit);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    if (responseTokenOverride == null) {
      await preferences.remove('max_response_tokens');
    } else {
      await preferences.setInt('max_response_tokens', responseTokenOverride!);
    }
  }

  Future<void> _loadLocalSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      onboarded = preferences.getBool('onboarding_complete') ?? false;
      final saved = preferences.getInt('max_response_tokens');
      if (saved != null) {
        responseTokenOverride = saved.clamp(128, responseTokenLimit);
      }
    } catch (error) {
      debugPrint('[AppState] local settings load failed: $error');
    } finally {
      localSettingsLoaded = true;
      notifyListeners();
    }
  }

  void selectModel(String name, String quant, {String? id}) {
    selectedModel = name;
    selectedModelQuant = quant;
    if (id != null) selectedModelId = id;
    notifyListeners();
  }

  void selectPersona(String name, {String? id}) {
    selectedPersonaId =
        id ??
        PersonaService.instance.all
            .where((persona) => persona.name == name)
            .firstOrNull
            ?.effectiveId ??
        PersonaService.instance.defaultPersona.effectiveId;
    notifyListeners();
  }

  Future<void> sharePersonaToOrg(String personaId) async {
    await orgState.sharePersona(personaId);
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    orgState.removeListener(_onOrgChanged);
    LocalServerService.instance.removeListener(_onServerChanged);
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
